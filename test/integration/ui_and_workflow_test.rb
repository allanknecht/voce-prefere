require "test_helper"
require "yaml"

class UiAndWorkflowTest < ActionDispatch::IntegrationTest
  test "every page has the 'acordando o servidor' notice, hidden by default, without inline style" do
    2.times { |i| Option.create!(text: "Opção #{i}", status: "approved") }
    [ root_path, pages_about_path, pairs_day_path, pairs_controversial_path, admin_login_path ].each do |path|
      get path
      assert_select "#slow-notice[hidden][role=status]", 1, path
      assert_select "#slow-notice[style]", 0, path
    end
  end

  test "the loading state script is first-party and ships with the forms working without JS" do
    get admin_login_path
    assert_select "form[method=post][action=?]", admin_login_path
    assert_select "input[type=password][required]"
    assert_select "input[type=submit]"
    js = Rails.root.join("app/assets/javascripts/application.js").read
    assert_includes js, "aria-busy"
    assert_no_match(%r{https?://}, js.gsub(%r{//.*$}, ""), "no third-party URL in the JS")
    assert_no_match(/eval\(|innerHTML|document\.write/, js)
  end

  test "CSS spinner respects prefers-reduced-motion" do
    css = Rails.root.join("app/assets/tailwind/application.css").read
    assert_match(/prefers-reduced-motion:\s*reduce/, css)
    assert_no_match(/@import\s+url|https?:\/\//, css)
  end

  test "/up does not use the database" do
    assert_equal 0, count_queries { get "/up" }.size
    assert_response :success
    assert_nil response.headers["Set-Cookie"]
  end

  test "keepalive workflow: every 10 minutes + manual, minimal permissions, only curls /up" do
    path = Rails.root.join(".github/workflows/keepalive.yml")
    yaml = YAML.safe_load(path.read, permitted_classes: [ Symbol ])
    triggers = yaml["on"] || yaml[true]
    assert_equal [ "*/10 * * * *" ], triggers["schedule"].map { |s| s["cron"] }
    assert triggers.key?("workflow_dispatch")
    assert_equal({}, yaml["permissions"])
    steps = yaml["jobs"].values.flat_map { |job| job["steps"] }
    assert_equal 1, steps.size
    assert_equal 'curl -fsS --max-time 60 "$URL/up"', steps.first["run"]
    refute_match(/secrets\./, path.read)
    assert_match(/vars\.KEEPALIVE_URL/, path.read)
  end

  test "there is no content filter left anywhere in the code base" do
    root = Rails.root
    files = Dir[root.join("{app,lib,config,db/seeds.rb,render.yaml,.env.example,README.md,DEPLOYMENT.md}/**/*"), root.join("render.yaml"), root.join(".env.example"), root.join("README.md"), root.join("DEPLOYMENT.md")]
            .select { |f| File.file?(f) }.reject { |f| f.include?("/db/migrate/") }
    offenders = files.select { |f| File.read(f).match?(/ContentModerator|MODERATION_(NAMES_)?BLOCKLIST/) && !f.end_with?("README.md", "DEPLOYMENT.md") }
    assert_empty offenders
    assert_not defined?(ContentModerator)
    assert_not root.join("app/services/content_moderator.rb").exist?
  end
end
