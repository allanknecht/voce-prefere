require "test_helper"

# Guards the number of SQL statements per public request (each one is a network round trip
# to Neon in production). Before this change, measured with the same data set (22 approved
# options, 30 pairs x 12 votes): home 3, /pairs/day 3, /pairs/:hash 4, /pairs/controversial 84,
# POST /votes 11, GET /about 0.
class QueryCountTest < ActionDispatch::IntegrationTest
  setup do
    RateLimiter::RateLimit.delete_all
    @options = Array.new(22) { |i| Option.create!(text: "Opção #{i}", status: "approved") }
    30.times do |i|
      a = @options[i % 22]
      b = @options[(i + 5) % 22]
      hash = PairGenerator.hash_for(a, b)
      12.times { |k| Vote.create!(option: k.even? ? a : b, pair_hash: hash) }
    end
    @pair_hash = PairGenerator.hash_for(@options[0], @options[5])
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown { Rails.cache = @original_cache }

  test "cold cache: home is 2 queries (approved options + one grouped vote query)" do
    assert_equal 2, count_queries { get root_path }.size
    assert_response :success
  end

  test "warm cache: home needs a single query" do
    get root_path
    assert_equal 1, count_queries { get root_path }.size
  end

  test "warm cache: /pairs/:hash and /pairs/day need a single query" do
    get pair_path(@pair_hash)
    get pairs_day_path
    assert_equal 1, count_queries { get pair_path(@pair_hash) }.size
    assert_equal 1, count_queries { get pairs_day_path }.size
    assert_response :success
  end

  test "controversial ranking: 2 queries fully cold (votes + approved options; was 84), none when cached" do
    assert_operator count_queries { get pairs_controversial_path }.size, :<=, 2
    assert_response :success
    assert_select "[data-width]"
    assert_equal 0, count_queries { get pairs_controversial_path }.size
  end

  test "static and health pages run no queries" do
    assert_equal 0, count_queries { get pages_about_path }.size
    assert_equal 0, count_queries { get "/up" }.size
  end

  test "vote: at most 5 queries (was 11, then 10 with the duplicate guard)" do
    headers = public_post_headers
    get root_path
    RateLimiter.last_cleanup = Process.clock_gettime(Process::CLOCK_MONOTONIC) # the expired-rows purge is throttled (once a minute per process)
    Rails.cache.fetch("vp:pairs:approved") { Option.approved.order(:id).to_a }
    queries = count_queries do
      post votes_path, params: { option_id: @options[0].id, pair_hash: @pair_hash }.to_json, headers: headers
    end
    assert_response :success
    assert_operator queries.size, :<=, 5, queries.join("\n")
  end

  test "no ORDER BY RANDOM anywhere in the public paths" do
    queries = count_queries do
      get root_path
      get pairs_day_path
      get pairs_controversial_path
    end
    refute queries.any? { |q| q.match?(/RANDOM\(\)|RAND\(\)/i) }
  end
end
