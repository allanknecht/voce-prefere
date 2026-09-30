# Builds the pairs shown on the public pages.
#
# Performance notes (Neon scales to zero and every round trip counts):
# * The approved options are cached in memory (Rails.cache, memory store, 60 s, and dropped as
#   soon as any Option changes), so picking a random pair / pair of the day / pair by hash needs
#   NO query at all. There is no ORDER BY RANDOM(): the pair is sampled in Ruby.
# * Nothing per visitor is ever cached: the random pair is drawn on every request from the
#   cached *list* of approved options.
# * The controversial ranking is computed with ONE query (instead of ~4 per pair) and cached
#   for a minute. The cache holds only public aggregates (option ids/texts, vote percentages).
class PairGenerator
  CACHE_NAMESPACE = "vp:pairs".freeze
  APPROVED_CACHE_TTL = 60.seconds
  CONTROVERSIAL_CACHE_TTL = 60.seconds

  def self.random_pair
    new.random_pair
  end

  def self.pair_of_day
    new.pair_of_day
  end

  # A pair different from `current_hash` (nil when there is no other pair at all).
  def self.next_pair(current_hash)
    new.next_pair(current_hash)
  end

  # An approved option by id straight from the in-memory list (no query), nil when not on air.
  def self.approved_option(id)
    new.approved_option(id)
  end

  def self.pair_by_hash(pair_hash)
    new.pair_by_hash(pair_hash)
  end

  def self.controversial_pairs(limit: 10, min_votes: 20)
    new.controversial_pairs(limit: limit, min_votes: min_votes)
  end

  def self.expire_caches!
    Rails.cache.delete_matched(/\A#{Regexp.escape(CACHE_NAMESPACE)}/)
  end

  # Canonical "smaller_id-bigger_id" key of a pair (also used for votes.pair_hash).
  def self.hash_for(option1, option2)
    [ option1.id, option2.id ].sort.join("-")
  end

  # Pairs are always good-vs-good or bad-vs-bad. A category is picked with a probability
  # proportional to its number of options (so every option is about as likely to show up),
  # then two different options of that category are drawn. Categories with a single option
  # cannot form a pair and are skipped.
  def random_pair
    pool = pairable_options
    return nil if pool.empty?

    total = pool.sum { |options| options.length }
    pick = rand(total)
    options = pool.find { |candidates| (pick -= candidates.length) < 0 }
    options.sample(2)
  end

  # "Próximo": decided by the server when the page is rendered (so the link is fixed, nothing
  # random happens at click time) and never the pair that is on the screen now.
  def next_pair(current_hash)
    12.times do
      pair = random_pair
      return pair if pair.nil? || hash_for(pair) != current_hash.to_s
    end
    # Unlucky draws (tiny catalogue): enumerate the remaining pairs.
    candidates = pairable_options.flat_map { |options| options.combination(2).to_a }
    candidates.reject { |pair| hash_for(pair) == current_hash.to_s }.sample
  end

  def approved_option(id)
    approved_options.find { |option| option.id == id }
  end

  def pair_of_day
    pool = pairable_options
    return nil if pool.empty?

    # Deterministic for the whole day (same seed for every visitor). String#hash is randomized
    # per process, so a stable CRC32 of the date is used as the seed instead.
    random = Random.new(Zlib.crc32(Date.current.to_s))
    pool.sort_by { |options| options.first.id }.sample(random: random).shuffle(random: random).take(2)
  end

  def pair_by_hash(pair_hash)
    option_ids = pair_hash.to_s.split("-").map(&:to_i).sort
    return nil if option_ids.length != 2 || option_ids.uniq.length != 2

    options_by_id(option_ids)
  end

  # Pairs closest to a 50/50 split with at least `min_votes` votes.
  # One query (candidate pairs as a subquery), cached for CONTROVERSIAL_CACHE_TTL.
  def controversial_pairs(limit: 10, min_votes: 20)
    Rails.cache.fetch("#{CACHE_NAMESPACE}:controversial:#{limit}:#{min_votes}", expires_in: CONTROVERSIAL_CACHE_TTL) do
      compute_controversial_pairs(limit: limit, min_votes: min_votes)
    end
  end

  private

  def hash_for(pair)
    self.class.hash_for(pair[0], pair[1])
  end

  # [[good options...], [bad options...]] without the categories that have fewer than 2 options
  def pairable_options
    approved_options.group_by(&:category).values.select { |options| options.length >= 2 }
  end

  def approved_options
    @approved_options ||= Rails.cache.fetch("#{CACHE_NAMESPACE}:approved", expires_in: APPROVED_CACHE_TTL) do
      Option.approved.order(:id).to_a
    end
  end

  def options_by_id(ids)
    found = approved_options.select { |option| ids.include?(option.id) }
    found.length == ids.length ? found : nil
  end

  def compute_controversial_pairs(limit:, min_votes:)
    # One query: per-option counts of the candidate pairs (index-only on votes(pair_hash, option_id)).
    candidates = Vote.group(:pair_hash).having("COUNT(*) >= ?", min_votes).select(:pair_hash)
    counts_by_pair = Vote.where(pair_hash: candidates).group(:pair_hash, :option_id).count
                         .each_with_object(Hash.new { |h, k| h[k] = {} }) { |((pair_hash, option_id), n), acc| acc[pair_hash][option_id] = n }

    ranked = counts_by_pair.map do |pair_hash, counts|
      percentages = Vote.percentages_from(counts)
      { pair_hash: pair_hash, percentages: percentages, total_votes: counts.values.sum, controversy: controversy_score(percentages) }
    end

    ranked = ranked.select { |pair| same_category?(pair[:pair_hash]) }
    ranked.sort_by { |pair| -pair[:controversy] }.filter_map do |pair|
      options = pair_by_hash(pair[:pair_hash])
      pair.merge(options: options) if options
    end.take(limit)
  end

  # Pairs made before categories existed may mix them; they are not ranked any more.
  def same_category?(pair_hash)
    options = pair_by_hash(pair_hash)
    options.present? && options.map(&:category).uniq.length == 1
  end

  # How close to 50/50 the split is (0-100, where 100 is a perfect 50/50)
  def controversy_score(percentages)
    values = percentages.values
    return 0 if values.length != 2

    100 - (values[0] - 50).abs
  end
end
