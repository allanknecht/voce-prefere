require "test_helper"

class PublicCacheTest < ActionDispatch::IntegrationTest
  setup do
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    @options = Array.new(6) { |i| Option.create!(text: "Opção #{i}", status: "approved") }
  end

  teardown { Rails.cache = @original_cache }

  test "/about is publicly cacheable, has an ETag, revalidates with 304, sets no cookie and no form token" do
    get pages_about_path
    assert_response :success
    assert_match(/public/, response.headers["Cache-Control"])
    assert_match(/max-age=600/, response.headers["Cache-Control"])
    assert response.headers["ETag"].present?
    assert_nil response.headers["Set-Cookie"]
    assert_select 'meta[name="form-token"]', 0

    get pages_about_path, headers: { "If-None-Match" => response.headers["ETag"] }
    assert_response :not_modified
    assert_nil response.headers["Set-Cookie"]
  end

  test "/pairs/controversial is publicly cacheable for a minute" do
    get pairs_controversial_path
    assert_response :success
    assert_match(/public/, response.headers["Cache-Control"])
    assert_match(/max-age=60/, response.headers["Cache-Control"])
    assert_nil response.headers["Set-Cookie"]
    assert_select 'meta[name="form-token"]', 0
  end

  test "pages with a per-visitor token or random content are never publicly cacheable" do
    pair = PairGenerator.hash_for(@options[0], @options[1])
    [ root_path, pairs_day_path, pair_path(pair), admin_login_path ].each do |path|
      get path
      assert_response :success, path
      cache_control = response.headers["Cache-Control"].to_s
      refute_match(/public/, cache_control, "#{path} must not be public")
      refute_match(/max-age=[1-9]/, cache_control, "#{path} must not be cached")
      assert_nil response.headers["Set-Cookie"], path
    end
  end

  test "the home page stays random per request" do
    seen = Set.new
    30.times do
      get root_path
      seen << css_select("#voting-container").first["data-pair-hash"]
    end
    assert_operator seen.size, :>, 1, "home served the same pair 30 times in a row"
  end

  test "approved options are cached in memory and dropped when an option changes" do
    queries = count_queries { 3.times { PairGenerator.random_pair } }
    assert_equal 1, queries.size

    Option.create!(text: "Nova aprovada", status: "approved")
    assert_equal 1, count_queries { PairGenerator.random_pair }.size # cache was dropped -> reloaded
    assert_includes PairGenerator.new.send(:approved_options).map(&:text), "Nova aprovada"

    Option.find_by!(text: "Nova aprovada").destroy_from_queue!
    refute_includes PairGenerator.new.send(:approved_options).map(&:text), "Nova aprovada"
  end

  test "pair of the day is the same for everybody on the same day" do
    day = PairGenerator.pair_of_day.map(&:id)
    assert_equal day, PairGenerator.pair_of_day.map(&:id)
    get pairs_day_path
    assert_select "#voting-container[data-pair-hash=?]", day.sort.join("-")
  end

  test "controversial ranking is cached, sorted by closeness to 50/50 and ignores pairs with too few votes" do
    close = PairGenerator.hash_for(@options[0], @options[1])
    far = PairGenerator.hash_for(@options[2], @options[3])
    few = PairGenerator.hash_for(@options[4], @options[5])
    6.times { Vote.create!(option: @options[0], pair_hash: close); Vote.create!(option: @options[1], pair_hash: close) }
    10.times { Vote.create!(option: @options[2], pair_hash: far) }
    2.times { Vote.create!(option: @options[3], pair_hash: far) }
    3.times { Vote.create!(option: @options[4], pair_hash: few) }

    ranking = PairGenerator.controversial_pairs(limit: 5, min_votes: 10)
    assert_equal [ close, far ], ranking.map { |r| r[:pair_hash] }
    assert_in_delta 100.0, ranking.first[:controversy], 0.1
    assert_equal 12, ranking.first[:total_votes]
    assert_equal 0, count_queries { PairGenerator.controversial_pairs(limit: 5, min_votes: 10) }.size
  end
end
