require "test_helper"

class AdminOptionsTest < ActionDispatch::IntegrationTest
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

  # Rails issues per-form tokens: take the one of the form that posts to `action`.
  def csrf_for(path, action:)
    get path
    css_select("form[action^='#{action}'] input[name=authenticity_token]").first["value"]
  end

  def make(text, status: "approved", **attrs)
    Option.create!(text: text, status: status, **attrs)
  end

  def listed_texts
    css_select("ul li p.font-bold").map { |n| n.text.strip }
  end

  # ---- auth ---------------------------------------------------------------------------

  test "every options-management route requires an admin session" do
    option = make("Protegida")
    get admin_options_path
    assert_redirected_to admin_login_path
    get edit_admin_option_path(option)
    assert_redirected_to admin_login_path
    get confirm_delete_admin_option_path(option)
    assert_redirected_to admin_login_path
    patch admin_option_path(option), params: { option: { text: "Hackeada" } }
    assert_includes [ 302, 422 ], response.status
    delete admin_option_path(option)
    assert_includes [ 302, 422 ], response.status
    assert_equal "Protegida", option.reload.text
    assert Option.exists?(option.id)
  end

  test "dashboard links to the management page" do
    login!
    get admin_index_path
    assert_select "a[href=?]", admin_options_path
  end

  # ---- listing: order, pagination, filters, search -----------------------------------------------

  test "lists all statuses alphabetically, case and accent insensitive" do
    make("zebra")
    make("Ávido", status: "pending")
    make("banana", status: "rejected")
    make("Abacaxi")
    make("ação")
    login!
    get admin_options_path
    assert_response :success
    assert_equal [ "Abacaxi", "ação", "Ávido", "banana", "zebra" ], listed_texts
    assert_equal "no-store", response.headers["Cache-Control"]
  end

  test "paginates 25 per page and keeps filter and search in the links" do
    30.times { |i| make("Opção %02d coisa" % i) }
    make("Outra pendente", status: "pending")
    login!
    get admin_options_path, params: { q: "coisa", status: "aprovadas" }
    assert_equal 25, listed_texts.size
    assert_equal "Opção 00 coisa", listed_texts.first
    assert_select "a[rel=next][href*='page=2'][href*='q=coisa'][href*='status=aprovadas']"
    assert_select "a[rel=prev]", 0

    get admin_options_path, params: { q: "coisa", status: "aprovadas", page: 2 }
    assert_equal 5, listed_texts.size
    assert_equal "Opção 29 coisa", listed_texts.last
    assert_select "a[rel=prev][href*='q=coisa']"
    assert_select "a[rel=next]", 0

    get admin_options_path, params: { page: 999 } # clamps to the last page
    assert_response :success
    get admin_options_path, params: { page: "abc" }
    assert_response :success
  end

  test "status filter" do
    make("Aprovada um")
    make("Pendente um", status: "pending")
    make("Rejeitada um", status: "rejected")
    login!
    { "aprovadas" => [ "Aprovada um" ], "pendentes" => [ "Pendente um" ], "rejeitadas" => [ "Rejeitada um" ],
      "" => [ "Aprovada um", "Pendente um", "Rejeitada um" ], "lixo" => [ "Aprovada um", "Pendente um", "Rejeitada um" ] }.each do |filter, expected|
      get admin_options_path, params: { status: filter }
      assert_equal expected, listed_texts, "filter #{filter.inspect}"
    end
  end

  test "search is case/accent insensitive and treats LIKE wildcards literally" do
    make("Ter 100% de bateria")
    make("Ter 100 de bateria")
    make("snake_case")
    make("snakeXcase")
    make("Comer AÇAÍ")
    make("barra \\ invertida")
    login!
    { "100%" => [ "Ter 100% de bateria" ], "%" => [ "Ter 100% de bateria" ], "snake_" => [ "snake_case" ],
      "_" => [ "snake_case" ], "acai" => [ "Comer AÇAÍ" ], "AÇAÍ" => [ "Comer AÇAÍ" ], "\\" => [ "barra \\ invertida" ],
      "'; DROP TABLE options; --" => [] }.each do |q, expected|
      get admin_options_path, params: { q: q }
      assert_response :success
      assert_equal expected, listed_texts, "search #{q.inspect}"
    end
    assert_equal 6, Option.count
  end

  test "row shows votes and reports counts" do
    a = make("Com votos", report_count: 2)
    b = make("Outra")
    3.times { Vote.create!(option: a, pair_hash: PairGenerator.hash_for(a, b)) }
    login!
    get admin_options_path
    assert_match(/3 votos • 2 denúncias/, response.body)
  end

  # ---- edit ---------------------------------------------------------------------------

  test "edit form renders and update saves stripped text, keeps status, expires the public cache" do
    a = make("Texto velho")
    make("Par")
    PairGenerator.random_pair # warms the approved-options cache
    login!
    get edit_admin_option_path(a, q: "velho")
    assert_select "form[action*='/admin/options/#{a.id}'] input[name=_method][value=patch]"

    token = csrf_for(edit_admin_option_path(a), action: admin_option_path(a))
    patch admin_option_path(a, q: "velho"), params: { option: { text: "  Texto novo  " }, authenticity_token: token }
    assert_redirected_to admin_options_path(q: "velho")
    assert_equal "Texto novo", a.reload.text
    assert_equal "approved", a.status
    assert_includes PairGenerator.new.send(:approved_options).map(&:text), "Texto novo"
    refute_includes PairGenerator.new.send(:approved_options).map(&:text), "Texto velho"
  end

  test "update validates: blank and too long texts are refused" do
    a = make("Original")
    login!
    token = csrf_for(edit_admin_option_path(a), action: admin_option_path(a))
    [ "   ", "x" * 121 ].each do |bad|
      patch admin_option_path(a), params: { option: { text: bad }, authenticity_token: token }
      assert_response :unprocessable_entity
      assert_equal "Original", a.reload.text
    end
  end

  test "duplicates (case/accent insensitive) are refused, even with force; the option itself may keep its text" do
    a = make("Comer açaí")
    b = make("Outra coisa")
    login!
    token = csrf_for(edit_admin_option_path(b), action: admin_option_path(b))
    patch admin_option_path(b), params: { option: { text: "COMER ACAI", force: "1" }, authenticity_token: token }
    assert_response :unprocessable_entity
    assert_match(/já existe/, response.body)
    assert_equal "Outra coisa", b.reload.text

    token_a = csrf_for(edit_admin_option_path(a), action: admin_option_path(a))
    patch admin_option_path(a), params: { option: { text: "Comer açaí " }, authenticity_token: token_a }
    assert_redirected_to admin_options_path
  end

  test "moderation hit shows a warning and needs the forçar checkbox" do
    a = make("Texto limpo")
    login!
    token = csrf_for(edit_admin_option_path(a), action: admin_option_path(a))
    flagged = "Votar em João Silva" # full-name heuristic, deterministic without env blocklists
    assert_equal false, ContentModerator.check(flagged)[:approved]

    patch admin_option_path(a), params: { option: { text: flagged }, authenticity_token: token }
    assert_response :unprocessable_entity
    assert_match(/filtro de moderação/, response.body)
    assert_select "input[type=checkbox][name='option[force]']"
    assert_equal "Texto limpo", a.reload.text

    patch admin_option_path(a), params: { option: { text: flagged, force: "1" }, authenticity_token: token }
    assert_redirected_to admin_options_path
    assert_equal flagged, a.reload.text
    assert_equal "approved", a.status
  end

  # ---- delete ---------------------------------------------------------------------------

  test "confirmation page states how many votes and reports go away; GET deletes nothing" do
    a = make("Vai sumir", report_count: 2)
    b = make("Fica")
    c = make("Terceira")
    2.times { Vote.create!(option: a, pair_hash: PairGenerator.hash_for(a, b)) }
    Vote.create!(option: b, pair_hash: PairGenerator.hash_for(a, b)) # vote on a pair containing a
    Vote.create!(option: b, pair_hash: PairGenerator.hash_for(b, c)) # unrelated
    login!
    get confirm_delete_admin_option_path(a)
    assert_response :success
    assert_match(/3 votos/, response.body)
    assert_match(/2 denúncias/, response.body)
    assert_select "form[action*='/admin/options/#{a.id}'] input[name=_method][value=delete]"
    assert Option.exists?(a.id)
  end

  test "delete removes the option, its votes (also on pairs containing it) and expires caches; unrelated votes stay" do
    a = make("Vai sumir", report_count: 2)
    b = make("Fica")
    c = make("Terceira")
    ab = PairGenerator.hash_for(a, b)
    bc = PairGenerator.hash_for(b, c)
    5.times { Vote.create!(option: a, pair_hash: ab) }
    5.times { Vote.create!(option: b, pair_hash: ab) }
    4.times { Vote.create!(option: b, pair_hash: bc) }
    PairGenerator.controversial_pairs(limit: 20, min_votes: 10) # warms the ranking cache
    get pair_path(ab)
    assert_response :success

    login!
    token = csrf_for(confirm_delete_admin_option_path(a), action: admin_option_path(a))
    assert_difference -> { Option.count }, -1 do
      delete admin_option_path(a, status: "aprovadas"), params: { authenticity_token: token }
    end
    assert_redirected_to admin_options_path(status: "aprovadas")
    assert_equal 0, Vote.where(option_id: a.id).count
    assert_equal 0, Vote.where(pair_hash: ab).count
    assert_equal 4, Vote.where(pair_hash: bc).count
    assert_empty PairGenerator.controversial_pairs(limit: 20, min_votes: 10)
    get pair_path(ab)
    assert_redirected_to root_path
    refute_includes PairGenerator.new.send(:approved_options).map(&:id), a.id
  end

  test "delete is atomic: if the option cannot be destroyed the votes are kept" do
    a = make("Atômica")
    b = make("Outra")
    Vote.create!(option: a, pair_hash: PairGenerator.hash_for(a, b))
    Option.class_eval do
      alias_method :__destroy_bang, :destroy!
      define_method(:destroy!) { raise ActiveRecord::RecordNotDestroyed, "boom" }
    end
    assert_raises(ActiveRecord::RecordNotDestroyed) { a.destroy_with_votes! }
    assert_equal 1, Vote.where(option_id: a.id).count
  ensure
    Option.class_eval do
      alias_method :destroy!, :__destroy_bang
      remove_method :__destroy_bang
    end
  end

  test "unknown id redirects back to the list" do
    login!
    get edit_admin_option_path(999_999)
    assert_redirected_to admin_options_path
  end

  # ---- CSRF ---------------------------------------------------------------------------

  test "PATCH and DELETE without the authenticity token are rejected and change nothing" do
    a = make("Sem token")
    login!
    patch admin_option_path(a), params: { option: { text: "Mudou" } }
    assert_response :unprocessable_entity
    delete admin_option_path(a)
    assert_response :unprocessable_entity
    patch admin_option_path(a), params: { option: { text: "Mudou" }, authenticity_token: "forged" }
    assert_response :unprocessable_entity
    a.reload
    assert_equal "Sem token", a.text
    assert Option.exists?(a.id)
  end
end
