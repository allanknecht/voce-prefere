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

  test "there is no filter of any kind on new options: anything within the length limit goes live" do
    [ "Votar em João Silva", "Dizer um palavrão qualquer", "Namorar a Maria da Silva" ].each do |text|
      submit(text: text, category: "bad")
      assert_response :success, text
      option = Option.find_by!(text: text)
      assert_equal [ "approved", true ], [ option.status, option.needs_review ]
    end
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
    assert_match(/category: category/, js)
    assert_no_match(%r{https?://}, js.gsub(%r{//.*$}, ""))
  end

  # ---- queue page --------------------------------------------------------------------------

  test "review page requires admin, is no-store, lists the queue (reported first, then oldest) and paginates 25" do
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
    assert_select "li a[href*='/admin/options/'][href*='/delete'][href*='from=review']", 25
    get admin_review_path(page: 2)
    assert_equal 5, css_select("ul li").size
  end

  test "dashboard shows the queue count with a highlighted link" do
    login!
    get admin_index_path
    assert_select "a[href=?]", admin_review_path, text: /Fila de revisão: 0 opções/
    assert_select "a[href=?].bg-gray-100", admin_review_path

    2.times { |i| make("Nova #{i}", needs_review: true) }
    make("Fora do ar antiga", status: "rejected", needs_review: true)
    get admin_index_path
    assert_select "a[href=?].bg-yellow-300", admin_review_path, text: /Fila de revisão: 3 opções/
  end

  test "Aprovar removes it from the queue, keeps it on air and resets the report count" do
    option = make("Denunciada", needs_review: true, report_count: 2)
    login!
    token = csrf_for(admin_review_path, action: admin_approve_path(option))
    post admin_approve_path(option), params: { authenticity_token: token }, headers: BROWSER_ADMIN_HEADERS
    assert_redirected_to admin_review_path
    option.reload
    assert_equal [ "approved", false, 0 ], [ option.status, option.needs_review, option.report_count ]
  end

  test "Excluir (confirmation page, then delete) removes the option for good with its votes and pair votes, and logs it" do
    a = make("Excluir esta", needs_review: true, category: "bad", report_count: 2)
    b = make("Par dela", category: "bad")
    c = make("Terceira", category: "bad")
    3.times { Vote.create!(option: a, pair_hash: PairGenerator.hash_for(a, b)) }
    2.times { Vote.create!(option: b, pair_hash: PairGenerator.hash_for(a, b)) }
    4.times { Vote.create!(option: b, pair_hash: PairGenerator.hash_for(b, c)) }
    login!
    get admin_review_path
    assert_select "a[href=?]", confirm_delete_admin_option_path(a, from: "review"), text: /Excluir/
    get confirm_delete_admin_option_path(a, from: "review")
    assert_match(/5 votos/, response.body)
    assert_match(/2 denúncias/, response.body)
    assert_select "a[href=?]", admin_review_path, text: "Cancelar"
    token = css_select("form[action^='/admin/options/#{a.id}'] input[name=authenticity_token]").first["value"]
    assert_difference -> { DeletedOption.count }, 1 do
      delete admin_option_path(a, from: "review"), params: { authenticity_token: token }, headers: BROWSER_ADMIN_HEADERS
    end
    assert_redirected_to admin_review_path
    refute Option.exists?(a.id)
    assert_equal 0, Vote.where(pair_hash: PairGenerator.hash_for(a, b)).count
    assert_equal 4, Vote.count
    entry = DeletedOption.last
    assert_equal [ "Excluir esta", "bad", "reprovada" ], [ entry.text, entry.category, entry.reason ]
    assert_equal "Excluída na fila", entry.reason_label
    refute_includes PairGenerator.new.send(:approved_options).map(&:id), a.id
  end

  test "there is no reject action any more, and the queue says Excluir, never Reprovar" do
    option = make("Texto qualquer da fila", needs_review: true)
    login!
    get admin_review_path
    assert_no_match(/Reprov/i, response.body)
    assert_match(/Excluir/, response.body)
    assert_raises(NoMethodError) { admin_reject_path(option) }
  end

  test "approve/delete need the admin session and the CSRF token" do
    option = make("Protegida", needs_review: true)
    post admin_approve_path(option), headers: BROWSER_ADMIN_HEADERS
    assert_includes [ 302, 422 ], response.status
    delete admin_option_path(option, from: "review"), headers: BROWSER_ADMIN_HEADERS
    assert_includes [ 302, 422 ], response.status
    assert Option.exists?(option.id)
    assert option.reload.needs_review
  end

  # ---- reports: nothing goes off air, reported options are queued and highlighted ---------------------------

  test "reports never take an option off the air: any number of them only counts and queues it" do
    option = make("Denunciável")
    other = make("Outra")
    assert_not option.needs_review
    1.upto(6) do |n|
      option.report!
      option.reload
      assert_equal [ "approved", true, n ], [ option.status, option.needs_review, option.report_count ]
    end
    assert_includes Option.approved, option
    assert_includes PairGenerator.new.send(:approved_options).map(&:id), option.id
    assert_includes Option.in_review, option
    refute_includes Option.in_review, other
  end

  test "the public report endpoint keeps the option live, queues it and keeps its rate limit" do
    option = make("Denunciada pelo público")
    make("Par")
    3.times do
      post report_option_path(option), headers: public_post_headers
      assert_response :success
    end
    option.reload
    assert_equal [ "approved", true, 3 ], [ option.status, option.needs_review, option.report_count ]
    get root_path
    assert_response :success
    assert_nil response.headers["Set-Cookie"]
    # rate limit: 10 reports per hour per (hashed) visitor
    7.times { post report_option_path(option), headers: public_post_headers }
    post report_option_path(option), headers: public_post_headers
    assert_response :too_many_requests
    assert_equal 10, option.reload.report_count
  end

  test "a report of an option that is not on the air is refused (the public cannot see it)" do
    hidden = make("Escondida", status: "rejected")
    post report_option_path(hidden), headers: public_post_headers
    assert_response :not_found
    assert_equal 0, hidden.reload.report_count
  end

  test "the queue lists reported options first (most reports first) with a highlighted report badge" do
    old = make("Antiga sem denúncia", needs_review: true, created_at: 3.days.ago)
    few = make("Com uma denúncia", needs_review: true, report_count: 1, created_at: 1.day.ago)
    many = make("Com cinco denúncias", needs_review: true, report_count: 5)
    login!
    get admin_review_path
    assert_equal [ many.text, few.text, old.text ], css_select("ul li p.font-bold").map { |n| n.text.strip }
    assert_match(/🚩 5 denúncias/, response.body)
    assert_match(/🚩 1 denúncia\b/, response.body)
    assert_select "li.border-red-500", 2
    assert_select "li.border-red-500 span.bg-red-600", 2
  end

  test "Aprovar resets the report count, so a later report queues it again" do
    option = make("Denunciada", needs_review: true, report_count: 4)
    login!
    token = csrf_for(admin_review_path, action: admin_approve_path(option))
    post admin_approve_path(option), params: { authenticity_token: token }, headers: BROWSER_ADMIN_HEADERS
    option.reload
    assert_equal [ "approved", false, 0 ], [ option.status, option.needs_review, option.report_count ]
    option.report!
    assert_equal [ 1, true ], [ option.reload.report_count, option.needs_review ]
  end

  # ---- hidden / rejected options: queue, Aprovar = on the air, Excluir = delete ---------------------------

  test "off-air options are listed in the queue with a 'Fora do ar' badge; Aprovar puts them on the air, Excluir deletes them" do
    rejected = make("Rejeitada antiga", status: "rejected", needs_review: true)
    pending = make("Pendente antiga", status: "pending", needs_review: true, report_count: 4)
    live = make("No ar", needs_review: true)
    login!
    get admin_review_path
    assert_equal 3, css_select("ul li").size
    assert_equal 2, css_select("ul li span").select { |n| n.text.strip == "Fora do ar" }.size
    assert_equal 1, css_select("ul li span").select { |n| n.text.strip == "No ar" }.size
    refute_includes Option.approved, rejected
    refute_includes PairGenerator.new.send(:approved_options).map(&:id), pending.id

    token = csrf_for(admin_review_path, action: admin_approve_path(rejected))
    post admin_approve_path(rejected), params: { authenticity_token: token }, headers: BROWSER_ADMIN_HEADERS
    rejected.reload
    assert_equal [ "approved", false, 0 ], [ rejected.status, rejected.needs_review, rejected.report_count ]
    assert_includes PairGenerator.new.send(:approved_options).map(&:id), rejected.id

    token = csrf_for(confirm_delete_admin_option_path(pending, from: "review"), action: admin_option_path(pending))
    delete admin_option_path(pending, from: "review"), params: { authenticity_token: token }, headers: BROWSER_ADMIN_HEADERS
    refute Option.exists?(pending.id)
    assert Option.exists?(live.id)
  end

  test "public pages never show a non-approved option" do
    6.times { |i| make("Visível #{i}") }
    hidden = [ make("Escondida rejeitada", status: "rejected", needs_review: true), make("Escondida pendente", status: "pending", needs_review: true) ]
    Vote.create!(option: hidden.first, pair_hash: PairGenerator.hash_for(*hidden))
    40.times do
      get root_path
      assert_no_match(/Escondida/, response.body)
    end
    [ pairs_day_path, pairs_controversial_path, pages_about_path ].each do |path|
      get path
      assert_no_match(/Escondida/, response.body, path)
    end
    get pair_path(PairGenerator.hash_for(*hidden))
    assert_redirected_to root_path
    post votes_path, params: { option_id: hidden.first.id, pair_hash: PairGenerator.hash_for(*hidden) }.to_json, headers: public_post_headers
    assert_response :not_found
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
    patch admin_option_path(option), params: { option: { text: "Mudar de lado", category: "bad" }, authenticity_token: token }, headers: BROWSER_ADMIN_HEADERS
    assert_redirected_to admin_options_path
    assert_equal "bad", option.reload.category
    assert_equal "bad", PairGenerator.new.send(:approved_options).find { |o| o.id == option.id }.category
  end

  test "an invalid category value is ignored" do
    option = make("Fica boa", category: "good")
    login!
    token = csrf_for(edit_admin_option_path(option), action: admin_option_path(option))
    patch admin_option_path(option), params: { option: { text: "Fica boa", category: "hacked" }, authenticity_token: token }, headers: BROWSER_ADMIN_HEADERS
    assert_equal "good", option.reload.category
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
