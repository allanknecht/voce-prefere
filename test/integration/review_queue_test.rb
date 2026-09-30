require "test_helper"

class ReviewQueueTest < ActionDispatch::IntegrationTest
  setup do
    https!
    RateLimiter::RateLimit.delete_all
    @cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown { Rails.cache = @cache }

  def login!
    get admin_login_path
    token = css_select("input[name=login_token]").first["value"]
    post admin_login_path, params: { secret: AdminSecret.value, login_token: token }, headers: { "Sec-Fetch-Site" => "same-origin" }
    assert_redirected_to admin_index_path
  end

  def csrf_for(path, action:)
    get path
    css_select("form[action^='#{action}'] input[name=authenticity_token]").first["value"]
  end

  def make(text, category: "good", **attrs)
    Option.create!(text: text, status: "approved", category: category, **attrs)
  end

  # ---- new options: live immediately + in the queue, no automatic moderation ------------------------

  def submit(attrs)
    post options_path, params: attrs.to_json, headers: public_post_headers
  end

  test "a submitted option is approved (live) at once and in the review queue, with the category the user chose" do
    { "good" => "Poder voar", "bad" => "Chutar a parede com um prego" }.each do |category, text|
      submit(text: text, category: category)
      assert_response :success
      option = Option.find_by!(text: text)
      assert_equal [ "approved", true, category ], [ option.status, option.needs_review, option.category ]
      assert_includes Option.approved, option
      assert_nil response.headers["Set-Cookie"]
    end
  end

  test "the chosen category wins over the classifier (no guessing for public submissions)" do
    submit(text: "Chutar a parede com um prego", category: "good")
    assert_equal "good", Option.find_by!(text: "Chutar a parede com um prego").category
    submit(text: "Ter super velocidade agora", category: "bad")
    assert_equal "bad", Option.find_by!(text: "Ter super velocidade agora").category
  end

  test "a missing or invalid category is refused with a clear message and nothing is created" do
    [ {}, { category: "" }, { category: nil }, { category: "GOOD" }, { category: "meh" }, { category: "boa" }, { category: [ "good" ] }, { category: { a: 1 } } ].each do |extra|
      assert_no_difference -> { Option.count } do
        submit({ text: "Sem categoria válida" }.merge(extra))
      end
      assert_response :unprocessable_entity, extra.inspect
      assert_equal "Escolha se a opção é Boa ou Ruim", response.parsed_body["error"]
      assert_nil response.headers["Set-Cookie"]
    end
  end

  test "there is no automatic moderation of new options: even text the blocklist flags goes live" do
    ENV["MODERATION_BLOCKLIST"] = "palavraoteste"
    ContentModerator.reset_lists!
    submit(text: "Dizer palavraoteste", category: "bad")
    option = Option.find_by!(text: "Dizer palavraoteste")
    assert_equal "approved", option.status
    assert option.needs_review
  ensure
    ENV.delete("MODERATION_BLOCKLIST")
    ContentModerator.reset_lists!
  end

  test "submission keeps the length/blank validation and the rate limit" do
    submit(text: "x" * 121, category: "good")
    assert_response :unprocessable_entity
    submit(text: "  ", category: "good")
    assert_response :unprocessable_entity
    5.times { |i| submit(text: "Opção limite #{i}", category: "good") }
    assert_response :success
    submit(text: "Opção além do limite", category: "good")
    assert_response :too_many_requests
    assert_nil Option.find_by(text: "Opção além do limite")
  end

  test "a public client cannot choose the status, review flag or report count" do
    submit(text: "Poder voar baixinho", category: "bad", status: "rejected", needs_review: false, report_count: 9, is_seed: true)
    option = Option.find_by!(text: "Poder voar baixinho")
    assert_equal [ "bad", "approved", true, 0, false ], [ option.category, option.status, option.needs_review, option.report_count, option.is_seed ]
  end

  test "the home page form has a required Boa/Ruim choice, nothing preselected, labelled in PT-BR" do
    get root_path
    assert_select "form#submit-form fieldset input[type=radio][name=category]", 2
    assert_select "input[type=radio][name=category][value=good][required]"
    assert_select "input[type=radio][name=category][value=bad][required]"
    assert_select "input[type=radio][name=category][checked]", 0
    assert_match(/Boa/, css_select("form#submit-form fieldset").text)
    assert_match(/Ruim/, css_select("form#submit-form fieldset").text)
    assert_select "form#submit-form [style], form#submit-form [onclick], form#submit-form script", 0
    js = Rails.root.join("app/assets/javascripts/application.js").read
    assert_match(/category: chosen\.value/, js)
    assert_no_match(%r{https?://}, js.gsub(%r{//.*$}, ""))
  end

  # ---- queue page --------------------------------------------------------------------------

  test "review page requires admin, is no-store, lists the queue oldest first and paginates 25" do
    get admin_review_path
    assert_redirected_to admin_login_path

    Option.create!(text: "Fora da fila", status: "approved", category: "good")
    30.times { |i| make("Na fila %02d" % i, needs_review: true, created_at: (40 - i).minutes.ago) }
    login!
    get admin_review_path
    assert_response :success
    assert_equal "no-store", response.headers["Cache-Control"]
    texts = css_select("ul li p.font-bold").map { |n| n.text.strip }
    assert_equal 25, texts.size
    assert_equal "Na fila 00", texts.first
    refute_includes texts, "Fora da fila"
    assert_select "a[rel=next][href*='page=2']"
    assert_select "li form[action^='/admin/approve/']", 25
    assert_select "li form[action^='/admin/reject/']", 25
    get admin_review_path(page: 2)
    assert_equal 5, css_select("ul li").size
  end

  test "dashboard shows the queue count with a highlighted link" do
    login!
    get admin_index_path
    assert_select "a[href=?]", admin_review_path, text: /Fila de revisão: 0 opções/
    assert_select "a[href=?].bg-gray-100", admin_review_path

    2.times { |i| make("Nova #{i}", needs_review: true) }
    get admin_index_path
    assert_select "a[href=?].bg-yellow-300", admin_review_path, text: /Fila de revisão: 2 opções/
  end

  test "Aprovar removes it from the queue, keeps it on air and resets the report count" do
    option = make("Denunciada", needs_review: true, report_count: 2)
    login!
    token = csrf_for(admin_review_path, action: admin_approve_path(option))
    post admin_approve_path(option), params: { authenticity_token: token }
    assert_redirected_to admin_review_path
    option.reload
    assert_equal [ "approved", false, 0 ], [ option.status, option.needs_review, option.report_count ]
  end

  test "Reprovar deletes the option for good with its votes and pair votes, and logs it as reprovada" do
    a = make("Reprovar esta", needs_review: true, category: "bad")
    b = make("Par dela", category: "bad")
    c = make("Terceira", category: "bad")
    3.times { Vote.create!(option: a, pair_hash: PairGenerator.hash_for(a, b)) }
    2.times { Vote.create!(option: b, pair_hash: PairGenerator.hash_for(a, b)) }
    4.times { Vote.create!(option: b, pair_hash: PairGenerator.hash_for(b, c)) }
    login!
    token = csrf_for(admin_review_path, action: admin_reject_path(a))
    assert_difference -> { DeletedOption.count }, 1 do
      post admin_reject_path(a), params: { authenticity_token: token }
    end
    refute Option.exists?(a.id)
    assert_equal 0, Vote.where(pair_hash: PairGenerator.hash_for(a, b)).count
    assert_equal 4, Vote.count
    entry = DeletedOption.last
    assert_equal [ "Reprovar esta", "bad", "reprovada" ], [ entry.text, entry.category, entry.reason ]
    refute_includes PairGenerator.new.send(:approved_options).map(&:id), a.id
  end

  test "approve/reject need the admin session and the CSRF token" do
    option = make("Protegida", needs_review: true)
    post admin_approve_path(option)
    assert_includes [ 302, 422 ], response.status
    post admin_reject_path(option)
    assert_includes [ 302, 422 ], response.status
    assert Option.exists?(option.id)
    assert option.reload.needs_review
  end

  # ---- reports: threshold 3 -> off air + back in the queue ----------------------------------------

  test "the third report takes an option off air and puts it in the queue; Aprovar puts it back" do
    option = make("Denunciável")
    make("Outra")
    2.times { option.report! }
    assert_equal [ "approved", false ], [ option.reload.status, option.needs_review ]
    option.report!
    option.reload
    assert_equal [ "pending", true, 3 ], [ option.status, option.needs_review, option.report_count ]
    refute_includes Option.approved, option
    assert_includes Option.in_review, option
    refute_includes PairGenerator.new.send(:approved_options).map(&:id), option.id

    option.approve!
    assert_equal [ "approved", false, 0 ], [ option.status, option.needs_review, option.report_count ]
    assert_includes PairGenerator.new.send(:approved_options).map(&:id), option.id
  end

  test "an off-air reported option is shown in the queue as off air" do
    option = make("Fora por denúncias")
    3.times { option.report! }
    login!
    get admin_review_path
    assert_match(/Fora do ar \(denúncias\)/, response.body)
    assert_match(/Fora por denúncias/, response.body)
  end

  test "a new option that gets reported is also pulled at the threshold" do
    option = make("Nova e denunciada", needs_review: true)
    3.times { option.report! }
    assert_equal "pending", option.reload.status
    assert option.needs_review
  end

  # ---- pairs only within a category ----------------------------------------------------------------

  test "random pairs, pair of the day and the home page never mix categories" do
    6.times { |i| make("Boa #{i}", category: "good") }
    6.times { |i| make("Ruim #{i}", category: "bad") }
    200.times do
      pair = PairGenerator.random_pair
      assert_equal 1, pair.map(&:category).uniq.length
    end
    day = PairGenerator.pair_of_day
    assert_equal 1, day.map(&:category).uniq.length
    assert_equal day.map(&:id), PairGenerator.pair_of_day.map(&:id)

    20.times do
      get root_path
      hash = css_select("#voting-container").first["data-pair-hash"]
      categories = Option.where(id: hash.split("-")).pluck(:category).uniq
      assert_equal 1, categories.length, hash
    end
  end

  test "both categories show up on the home page" do
    6.times { |i| make("Boa #{i}", category: "good") }
    6.times { |i| make("Ruim #{i}", category: "bad") }
    seen = Set.new
    80.times { seen << PairGenerator.random_pair.first.category }
    assert_equal Set["good", "bad"], seen
  end

  test "a category with a single option is skipped, and no pair exists when no category has two" do
    make("Única boa", category: "good")
    make("Única ruim", category: "bad")
    assert_nil PairGenerator.random_pair
    assert_nil PairGenerator.pair_of_day
    get root_path
    assert_response :success
    make("Segunda ruim", category: "bad")
    20.times { assert_equal %w[bad bad], PairGenerator.random_pair.map(&:category) }
  end

  test "controversial ranking ignores old mixed-category pairs" do
    good = make("Boa", category: "good")
    bad = make("Ruim", category: "bad")
    other = make("Ruim 2", category: "bad")
    mixed = PairGenerator.hash_for(good, bad)
    same = PairGenerator.hash_for(bad, other)
    6.times { Vote.create!(option: good, pair_hash: mixed); Vote.create!(option: bad, pair_hash: mixed) }
    6.times { Vote.create!(option: bad, pair_hash: same); Vote.create!(option: other, pair_hash: same) }
    assert_equal [ same ], PairGenerator.controversial_pairs(limit: 5, min_votes: 10).map { |r| r[:pair_hash] }
  end

  # ---- admin: category filter and change ---------------------------------------------------------------

  test "/admin/options filters by category and keeps it in pagination links" do
    30.times { |i| make("Boa %02d" % i, category: "good") }
    make("Ruim única", category: "bad")
    login!
    get admin_options_path, params: { category: "ruins" }
    assert_equal [ "Ruim única" ], css_select("ul li p.font-bold").map { |n| n.text.strip }
    get admin_options_path, params: { category: "boas" }
    assert_equal 25, css_select("ul li p.font-bold").size
    assert_select "a[rel=next][href*='category=boas']"
    get admin_options_path, params: { category: "lixo" }
    assert_equal 25, css_select("ul li p.font-bold").size
    assert_select "select[name=category] option[value=ruins]"
  end

  test "admin changes the category of an option (and pairs follow)" do
    option = make("Mudar de lado", category: "good")
    login!
    token = csrf_for(edit_admin_option_path(option), action: admin_option_path(option))
    assert_select "input[type=radio][name='option[category]'][value=bad]"
    patch admin_option_path(option), params: { option: { text: "Mudar de lado", category: "bad" }, authenticity_token: token }
    assert_redirected_to admin_options_path
    assert_equal "bad", option.reload.category
    assert_equal "bad", PairGenerator.new.send(:approved_options).find { |o| o.id == option.id }.category
  end

  test "an invalid category value is ignored" do
    option = make("Fica boa", category: "good")
    login!
    token = csrf_for(edit_admin_option_path(option), action: admin_option_path(option))
    patch admin_option_path(option), params: { option: { text: "Fica boa", category: "hacked" }, authenticity_token: token }
    assert_equal "good", option.reload.category
  end

  test "a moderation hit on an admin edit still warns and needs forçar" do
    option = make("Texto normal")
    login!
    token = csrf_for(edit_admin_option_path(option), action: admin_option_path(option))
    patch admin_option_path(option), params: { option: { text: "Votar em João Silva" }, authenticity_token: token }
    assert_response :unprocessable_entity
    assert_match(/filtro de moderação/, response.body)
  end

  # ---- public pages keep working and stay cookie-free ---------------------------------------------------

  test "public pages set no cookie and the loading/CSP rules still hold" do
    4.times { |i| make("Boa #{i}") }
    [ root_path, pages_about_path, pairs_day_path, pairs_controversial_path ].each do |path|
      get path
      assert_nil response.headers["Set-Cookie"], path
      assert_select "script:not([src])", 0
    end
  end
end
