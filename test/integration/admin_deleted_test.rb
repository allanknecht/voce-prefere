require "test_helper"

class AdminDeletedTest < ActionDispatch::IntegrationTest
  setup do
    https!
    RateLimiter::RateLimit.delete_all
  end

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

  test "auth required (no cookie set either)" do
    get admin_deleted_path
    assert_redirected_to admin_login_path
    assert_nil response.headers["Set-Cookie"]
  end

  test "dashboard links to the page" do
    login!
    get admin_index_path
    assert_select "a[href=?]", admin_deleted_path
  end

  test "lists most recent first, paginated 25, no-store, read-only (no forms/buttons), shows text, category, reason, date" do
    30.times { |i| DeletedOption.create!(text: "Excluída %02d" % i, reason: "manual", deleted_at: i.minutes.ago) }
    DeletedOption.create!(text: "Reprovada agora", category: "comida", reason: "reprovada", deleted_at: Time.current + 1.minute)
    login!
    get admin_deleted_path
    assert_response :success
    assert_equal "no-store", response.headers["Cache-Control"]
    texts = css_select("ul li p.font-bold").map { |n| n.text.strip }
    assert_equal 25, texts.size
    assert_equal "Reprovada agora", texts.first
    assert_equal "Excluída 23", texts.last
    assert_match(/Reprovada/, response.body)
    assert_match(/Categoria: comida/, response.body)
    assert_match(%r{\d{2}/\d{2}/\d{4} \d{2}:\d{2}}, response.body)
    assert_select "ul form, ul button, ul input", 0
    assert_select "a[rel=next][href*='page=2']"

    get admin_deleted_path(page: 2)
    assert_equal 6, css_select("ul li").size
    assert_equal "Excluída 29", css_select("ul li p.font-bold").last.text.strip
    get admin_deleted_path(page: 99)
    assert_response :success
  end

  test "there are no routes to change the log" do
    login!
    assert_no_difference -> { DeletedOption.count } do
      post "/admin/deleted"
      assert_response :not_found
      delete "/admin/deleted/1"
      assert_response :not_found
      patch "/admin/deleted/1"
      assert_response :not_found
    end
  end

  test "manual delete via /admin/options records the text and category (reason manual)" do
    option = Option.create!(text: "Vai pro log", status: "approved", category: "bad")
    login!
    token = csrf_for(confirm_delete_admin_option_path(option), action: admin_option_path(option))
    assert_difference -> { DeletedOption.count }, 1 do
      delete admin_option_path(option), params: { authenticity_token: token }, headers: BROWSER_ADMIN_HEADERS
    end
    entry = DeletedOption.last
    assert_equal [ "Vai pro log", "bad", "manual" ], [ entry.text, entry.category, entry.reason ]
    refute Option.exists?(option.id)
    get admin_deleted_path
    assert_match(/Vai pro log/, response.body)
  end

  test "Reprovar in the review queue records the text (reason reprovada)" do
    option = Option.create!(text: "Reprovada na fila", status: "approved", needs_review: true)
    login!
    token = csrf_for(admin_review_path, action: admin_reject_path(option))
    assert_difference -> { DeletedOption.count }, 1 do
      post admin_reject_path(option), params: { authenticity_token: token }, headers: BROWSER_ADMIN_HEADERS
    end
    refute Option.exists?(option.id), "Reprovar deletes the option for good"
    assert_equal [ "Reprovada na fila", "reprovada" ], DeletedOption.last.then { |e| [ e.text, e.reason ] }
  end

  test "any deletion path (destroy) logs the text" do
    option = Option.create!(text: "Via destroy", status: "approved")
    assert_difference -> { DeletedOption.count }, 1 do
      option.destroy!
    end
    assert_equal "manual", DeletedOption.last.reason
  end

  test "rollback atomicity: if the delete fails nothing is logged, and if the log fails nothing is deleted" do
    a = Option.create!(text: "Atômica", status: "approved")
    b = Option.create!(text: "Par", status: "approved")
    Vote.create!(option: a, pair_hash: PairGenerator.hash_for(a, b))

    # 1. the log write fails -> option and votes stay
    DeletedOption.singleton_class.alias_method :__orig_record!, :record!
    DeletedOption.define_singleton_method(:record!) { |*, **| raise ActiveRecord::StatementInvalid, "boom" }
    begin
      assert_raises(ActiveRecord::StatementInvalid) { a.destroy_with_votes! }
      assert_raises(ActiveRecord::StatementInvalid) { a.reject! }
    ensure
      DeletedOption.singleton_class.alias_method :record!, :__orig_record!
      DeletedOption.singleton_class.remove_method :__orig_record!
    end
    assert Option.exists?(a.id)
    assert_equal "approved", a.reload.status
    assert_equal 1, Vote.where(option_id: a.id).count
    assert_equal 0, DeletedOption.count

    # 2. the delete fails after the log was written -> the log row is rolled back too
    Option.class_eval do
      alias_method :__destroy_bang, :destroy!
      define_method(:destroy!) { raise ActiveRecord::RecordNotDestroyed, "boom" }
    end
    begin
      assert_raises(ActiveRecord::RecordNotDestroyed) { a.destroy_with_votes! }
    ensure
      Option.class_eval do
        alias_method :destroy!, :__destroy_bang
        remove_method :__destroy_bang
      end
    end
    assert_equal 0, DeletedOption.count
    assert_equal 1, Vote.where(option_id: a.id).count
  end

  test "the table holds no personal or linking data" do
    columns = DeletedOption.column_names.sort
    assert_equal %w[category deleted_at id reason text], columns
    refute columns.any? { |c| c.match?(/ip|user|author|email|session|hash|option_id|agent/) }
  end

  test "invalid reason is refused" do
    assert_raises(ArgumentError, ActiveRecord::RecordInvalid) { DeletedOption.create!(text: "x", reason: "outra") }
  end
end
