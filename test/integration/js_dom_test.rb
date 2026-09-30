require "test_helper"
require "open3"

# Static checks of the site's only script + (when jsdom is installed on the machine, it is NOT a
# dependency of the app) a DOM simulation: double click -> one fetch, all buttons locked at once,
# errors re-enable. See test/js/application_dom_test.js.
class JsDomTest < ActiveSupport::TestCase
  JS = Rails.root.join("app/assets/javascripts/application.js")

  test "the script is syntactically valid (node --check) when node is available" do
    skip "node not installed" unless system("which node > /dev/null 2>&1")
    _, err, status = Open3.capture3("node", "--check", JS.to_s)
    assert status.success?, err
  end

  test "static: one script, no inline handlers, no third-party hosts, locks set before fetch" do
    source = JS.read
    code = source.gsub(%r{//.*$}, "")
    assert_no_match(%r{https?://}, code)
    assert_no_match(/\beval\(|new Function|document\.write|innerHTML/, code)
    assert_match(/voteLocked = true;\s*\n\s*lockVoting\(true, button\);/, source)
    assert_match(/submitLocked = true;/, source)
    assert_match(/AbortController/, source)
    assert_match(/Enviando\.\.\./, source)
    assert_no_match(/onclick=|onsubmit=/, Rails.root.join("app/views").glob("**/*.erb").map(&:read).join)
  end

  test "DOM simulation in jsdom (double click, locks, errors, timeouts)" do
    skip "node not installed" unless system("which node > /dev/null 2>&1")
    node_path = [ ENV["NODE_PATH"], "/tmp/jsd/node_modules" ].compact.join(":")
    has_jsdom = system({ "NODE_PATH" => node_path }, "node", "-e", "require('jsdom')", out: File::NULL, err: File::NULL)
    skip "jsdom not installed (npm i jsdom@24; not an app dependency)" unless has_jsdom
    out, status = Open3.capture2e({ "NODE_PATH" => node_path }, "node", Rails.root.join("test/js/application_dom_test.js").to_s)
    assert status.success?, out
    assert_match(/all passed/, out)
  end
end
