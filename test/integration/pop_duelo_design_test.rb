require "test_helper"

# The "Pop Duelo" redesign must keep working under the strict CSP: no inline style, bars sized by
# classes, the font self-hosted, and every public screen using the shared look.
class PopDueloDesignTest < ActionDispatch::IntegrationTest
  setup do
    @good = Array.new(3) { |i| Option.create!(text: "Boa número #{i}", status: "approved", category: "good") }
    @pair = PairGenerator.hash_for(@good[0], @good[1])
    12.times { Vote.create!(option: @good[0], pair_hash: @pair) }
    4.times { Vote.create!(option: @good[1], pair_hash: @pair) }
  end

  test "vote buttons: two options tagged A/B with a VS badge, labels in natural case (CSS upper-cases them)" do
    get pair_path(@pair)
    assert_select "#voting-container .duel .vote-button", 2
    assert_select ".vote-button.opt-a .opt-tag", text: "Opção A"
    assert_select ".vote-button.opt-b .opt-tag", text: "Opção B"
    assert_select ".duel .vs[aria-hidden=true]", text: "VS"
    assert_select ".vote-button .opt-text", text: @good[0].text
  end

  test "result bars: no inline style, the width is a .bar-w-N class plus data-width, leader is highlighted" do
    get pair_results_path(@pair)
    assert_select "[style]", 0
    assert_select "[data-option-id$='-bar'].bar-w-75[data-width='75.0']", 1
    assert_select "[data-option-id$='-bar'].bar-w-25[data-width='25.0']", 1
    assert_select ".bar-row.is-winner", 1
    assert_select ".bar-row.is-winner .bar-label", text: @good[0].text
  end

  test "an empty bar (no votes yet) is bar-w-0 and nobody is highlighted" do
    get pair_results_path(PairGenerator.hash_for(@good[1], @good[2]))
    assert_select ".bar-fill.bar-w-0", 2
    assert_select ".bar-row.is-winner", 0
  end

  test "submit modal: labelled dialog with the Boa/Ruim radios and the ids the script uses" do
    get root_path
    assert_select "#submit-modal.modal-backdrop.hidden .modal[role=dialog][aria-modal=true][aria-labelledby=submit-title]"
    assert_select "#submit-title", text: /Envie sua opção/
    assert_select "label[for=option-text]"
    assert_select "fieldset legend", text: /Essa opção é/
    assert_select ".choices input[type=radio][name=category]", 2
    assert_select "#submit-form button[type=submit]", 1
    assert_select "#cancel-button", 1
    assert_select "#submit-message[role=status]", 1
  end

  test "public pages use landmarks: one h1, one main, no Tailwind gradient leftovers" do
    [ root_path, pairs_day_path, pages_about_path, pairs_controversial_path ].each do |path|
      get path
      assert_response :success, path
      assert_select "h1", 1, path
      assert_select "main", 1, path
      assert_select "body.admin-area", 0, path
      assert_select "[class*=bg-gradient]", 0, path
    end
  end

  test "Polêmicos is an ordered list of ranked cards" do
    Vote.delete_all
    Option.where.not(id: @good[0..1].map(&:id)).delete_all
    6.times { Vote.create!(option: @good[0], pair_hash: @pair) }
    6.times { Vote.create!(option: @good[1], pair_hash: @pair) }
    PairGenerator.controversial_pairs(limit: 20, min_votes: 10) # warm
    Rails.cache.clear
    get pairs_controversial_path
    assert_select "ol.rank-list li.rank-item", 1
    assert_select "li.rank-item .rank-num", text: "#1"
    assert_select "li.rank-item .bar-fill[data-width='50.0'].bar-w-50", 2
    assert_select "li.rank-item a.btn-small[href=?]", pair_path(@pair)
  end

  test "the stylesheet self-hosts Archivo Black (digested /assets URL) and nothing external" do
    get root_path
    href = css_select("link[rel=stylesheet]").first["href"]
    get href
    css = response.body.dup.force_encoding("UTF-8").sub(%r{\A/\*!.*?\*/}m, "") # minus the license banner (it links to tailwindcss.com)
    assert_match(%r!@font-face\{font-family:"?Archivo Black"?[^}]*url\("?/assets/ArchivoBlack-Regular-[0-9a-f]+\.woff2"?\)!, css)
    assert_no_match(%r{https?://|@import\s+url}, css)
    assert_match(/prefers-color-scheme:\s*dark/, css)
    assert_match(/prefers-reduced-motion:\s*reduce/, css)
    font = css[%r{/assets/ArchivoBlack-Regular-[0-9a-f]+\.woff2}]
    get font
    assert_response :success
    assert_equal "font/woff2", response.media_type
    assert_equal "wOF2", response.body.byteslice(0, 4)
    assert Rails.root.join("app/assets/fonts/OFL.txt").read.include?("SIL OPEN FONT LICENSE")
  end

  test "vote button states are styled from the attributes/classes the script sets" do
    css = Rails.root.join("app/assets/tailwind/application.css").read
    [ ".vote-button[disabled]", '.vote-button[aria-busy="true"]', ".vote-button.is-loading", ".vote-button.vote-chosen", "[aria-disabled=\"true\"]", ".slow-notice" ].each do |selector|
      assert_includes css, selector
    end
  end

  test "static error pages: Portuguese, first-party stylesheet only, no inline style or script" do
    css = Rails.root.join("public/erro-v1.css").read
    assert_no_match(%r{https?://|@import}, css)
    %w[400 404 406-unsupported-browser 422 500].each do |name|
      html = Rails.root.join("public/#{name}.html").read
      assert_match(/lang="pt-BR"/, html, name)
      assert_match(%r{<link rel="stylesheet" href="/erro-v1.css">}, html, name)
      assert_no_match(/<style|style=|<script|onclick=/, html, name)
      assert_match(/Voltar ao início/, html, name)
    end
  end

  test "admin pages keep the light palette class" do
    https!
    get admin_login_path
    assert_select "body.admin-area main.wrap"
  end
end
