require "test_helper"

# Fast/safe public interactions: server idempotency of votes, duplicate submissions, deterministic
# "Próximo", and no stale cached HTML for pages with a random pair.
class FastVoteAndNextTest < ActionDispatch::IntegrationTest
  setup do
    RateLimiter::RateLimit.delete_all
    @good = Array.new(5) { |i| Option.create!(text: "Boa #{i}", status: "approved", category: "good") }
    @bad = Array.new(4) { |i| Option.create!(text: "Ruim #{i}", status: "approved", category: "bad") }
    @pair = PairGenerator.hash_for(@good[0], @good[1])
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown { Rails.cache = @original_cache }

  def vote(option, pair = @pair, ip: nil, headers: public_post_headers)
    extra = ip ? { "REMOTE_ADDR" => ip } : {}
    post votes_path, params: { option_id: option.id, pair_hash: pair }.to_json, headers: headers, env: extra
  end

  # ---- vote idempotency ---------------------------------------------------------------------------

  test "a double vote on the same pair by the same visitor within 10 s is counted once and answers the same success" do
    vote(@good[0])
    assert_response :success
    first = response.parsed_body
    vote(@good[0]) # double click that got through
    assert_response :success
    assert_equal first, response.parsed_body
    vote(@good[1]) # even the other button of the same pair within the window
    assert_response :success
    assert_equal 1, Vote.where(pair_hash: @pair).count
    assert_equal 1, first["total_votes"]
  end

  test "a different pair, or a different visitor, still counts" do
    vote(@good[0])
    other_pair = PairGenerator.hash_for(@good[2], @good[3])
    vote(@good[2], other_pair)
    assert_equal 1, Vote.where(pair_hash: other_pair).count
    vote(@good[0], @pair, ip: "10.9.8.7")
    assert_equal 2, Vote.where(pair_hash: @pair).count
  end

  test "after the 10 s window the same visitor can vote on that pair again" do
    vote(@good[0])
    RateLimiter::RateLimit.where(action: "once").update_all(expires_at: 1.second.ago)
    vote(@good[0])
    assert_equal 2, Vote.where(pair_hash: @pair).count
  end

  test "the duplicate guard stores only a salted hash, with a 10 s expiry, and no cookie is set" do
    vote(@good[0])
    assert_nil response.headers["Set-Cookie"]
    row = RateLimiter::RateLimit.find_by!(action: "once")
    assert_equal 64, row.hashed_key.length
    refute_includes row.hashed_key, "127.0.0.1"
    assert_in_delta 10, row.expires_at - Time.current, 2
  end

  test "claim_once is atomic: exactly one of many claims wins" do
    results = Array.new(5) { RateLimiter.claim_once("1.2.3.4", "k", 10.seconds) }
    assert_equal [ true ], results.uniq.select { |r| r } # one winner...
    assert_equal 1, results.count(true)
  end

  test "rejected or unknown options are still refused and never counted" do
    hidden = Option.create!(text: "Fora", status: "rejected", category: "good")
    vote(hidden, "#{@good[0].id}-#{hidden.id}")
    assert_response :not_found
    post votes_path, params: { option_id: @good[0].id, pair_hash: "abc" }.to_json, headers: public_post_headers
    assert_response :unprocessable_entity
    assert_equal 0, Vote.count
  end

  test "vote request: at most 5 queries (was 10)" do
    get root_path
    RateLimiter.last_cleanup = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    vote(@good[2], PairGenerator.hash_for(@good[2], @good[3])) # warm-up (approved list cache)
    headers = public_post_headers
    queries = count_queries { vote(@good[0], headers: headers) }
    assert_response :success
    assert_operator queries.size, :<=, 5, queries.join("\n")
  end

  # ---- duplicate submissions ---------------------------------------------------------------------

  def submit(text, category = "good")
    post options_path, params: { text: text, category: category }.to_json, headers: public_post_headers
  end

  test "submitting the same text twice (case/accent/space-insensitive) is refused with a friendly 422" do
    submit("Comer açaí")
    assert_response :success
    [ "Comer açaí", "COMER ACAI", "  comer   acaí " ].each do |text|
      submit(text)
      assert_response :unprocessable_entity, text
      assert_equal "Essa opção já existe! Envie outra.", response.parsed_body["error"]
    end
    assert_equal 1, Option.where("text LIKE ?", "%ç%").count
  end

  test "two simultaneous identical submits cannot both insert: the unique index turns the loser into the friendly 422" do
    submit("Corrida identica")
    assert_response :success
    # the loser of the race already passed both application-level checks (text_taken? and the
    # model validation); only the UNIQUE index can stop it
    original_taken = Option.method(:text_taken?)
    Option.define_singleton_method(:text_taken?) { |*| false }
    Option.class_eval do
      alias_method :__orig_text_key_free, :text_key_free
      define_method(:text_key_free) { nil }
    end
    begin
      submit("corrida IDENTICA")
      assert_response :unprocessable_entity
      assert_equal "Essa opção já existe! Envie outra.", response.parsed_body["error"]
    ensure
      Option.class_eval { alias_method :text_key_free, :__orig_text_key_free }
      Option.define_singleton_method(:text_taken?, original_taken)
    end
    assert_equal 1, Option.where(text_key: "corrida identica").count
  end

  test "the UNIQUE index on text_key is real" do
    Option.create!(text: "Única", status: "approved", category: "good")
    assert_raises(ActiveRecord::RecordNotUnique) do
      Option.transaction(requires_new: true) { Option.insert!({ text: "unica", text_key: "unica", status: "approved", category: "good", report_count: 0, is_seed: false, needs_review: false }) }
    end
    assert_includes ActiveRecord::Base.connection.indexes(:options).map(&:name), "index_options_on_text_key"
  end

  test "admin edit still refuses a duplicate and keeps text_key in sync" do
    a = Option.create!(text: "Primeira", status: "approved", category: "good")
    b = Option.create!(text: "Segunda", status: "approved", category: "good")
    b.text = "primeira"
    refute b.valid?(:admin_edit)
    a.update!(text: "Renomeada")
    assert_equal "renomeada", a.reload.text_key
    assert Option.create!(text: "Primeira", status: "approved", category: "good").persisted? # the old text is free now
  end

  # ---- deterministic "Próximo" -------------------------------------------------------------------

  def next_href
    css_select("#results a.btn-next").first["href"]
  end

  test "Próximo points to /pairs/:hash fixed at render time: never the current pair, same category, both options on air" do
    40.times do
      get root_path
      current = css_select("#voting-container").first["data-pair-hash"]
      href = next_href
      assert_match(%r{\A/pairs/\d+-\d+\z}, href)
      target = href.delete_prefix("/pairs/")
      refute_equal current, target
      options = PairGenerator.pair_by_hash(target)
      assert options, "the target pair is on air"
      assert_equal 1, options.map(&:category).uniq.size
      assert_equal 1, PairGenerator.pair_by_hash(current).map(&:category).uniq.size
    end
  end

  test "the link target is stable for the life of the page and the target page renders it (chain of Próximo clicks)" do
    get root_path
    seen = [ css_select("#voting-container").first["data-pair-hash"] ]
    6.times do
      href = next_href
      get href
      assert_response :success
      seen << css_select("#voting-container").first["data-pair-hash"]
      assert_equal href.delete_prefix("/pairs/"), seen.last
      refute_equal seen[-2], seen[-1]
    end
  end

  test "with exactly one possible pair, there are no candidates and the page falls back to the home link" do
    Option.where.not(id: [ @good[0].id, @good[1].id ]).delete_all
    PairGenerator.expire_caches!
    assert_empty NextPairSelector.candidates(@pair)
    get pair_path(@pair)
    assert_response :success
    assert_equal "/", next_href
  end

  test "pages with a random pair or a form token are never cached by browsers or Cloudflare" do
    [ root_path, pair_path(@pair), pairs_day_path ].each do |path|
      get path
      cache_control = response.headers["Cache-Control"]
      assert_match(/private/, cache_control, path)
      assert_match(/no-cache/, cache_control, path)
      assert_match(/max-age=0/, cache_control, path)
      refute_match(/public/, cache_control, path)
      assert_nil response.headers["Set-Cookie"], path
    end
  end

  test "the home page is still random per request" do
    seen = Set.new
    40.times { get root_path; seen << css_select("#voting-container").first["data-pair-hash"] }
    assert_operator seen.size, :>, 1
  end

  # ---- repository hygiene ------------------------------------------------------------------------------

  test "no stray scratch files in the repository root" do
    stray = Dir[Rails.root.join("*.{txt,html}")].map { |f| File.basename(f) }
    assert_empty stray
  end
end
