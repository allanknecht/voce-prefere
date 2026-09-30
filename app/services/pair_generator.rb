class PairGenerator
  def self.random_pair
    new.random_pair
  end

  def self.pair_of_day
    new.pair_of_day
  end

  def self.pair_by_hash(pair_hash)
    new.pair_by_hash(pair_hash)
  end

  def self.controversial_pairs(limit: 10, min_votes: 20)
    new.controversial_pairs(limit: limit, min_votes: min_votes)
  end

  def initialize
    @approved_options = Option.approved.to_a
  end

  def random_pair
    return nil if @approved_options.length < 2
    @approved_options.sample(2)
  end

  def pair_of_day
    return nil if @approved_options.length < 2

    # Deterministic pair based on today's date
    date_seed = Date.current.to_s
    @approved_options.shuffle(random: Random.new(date_seed.hash)).take(2)
  end

  def pair_by_hash(pair_hash)
    # Extract option IDs from hash and verify
    option_ids = pair_hash.split("-").map(&:to_i).sort
    return nil if option_ids.length != 2

    options = Option.approved.where(id: option_ids).to_a
    return nil if options.length != 2

    options
  end

  def controversial_pairs(limit: 10, min_votes: 20)
    # Find pairs closest to 50/50 with minimum vote count
    pair_stats = Vote
      .group(:pair_hash)
      .having("COUNT(*) >= ?", min_votes)
      .count
      .map { |pair_hash, total_votes| [ pair_hash, total_votes ] }
      .sort_by { |pair_hash, _| controversy_score(pair_hash) }
      .reverse
      .take(limit)

    pair_stats.map do |(pair_hash, total_votes)|
      options = pair_by_hash(pair_hash)
      next unless options

      percentages = Vote.pair_stats(pair_hash)
      {
        pair_hash: pair_hash,
        options: options,
        percentages: percentages,
        total_votes: total_votes,
        controversy: controversy_score(pair_hash)
      }
    end.compact
  end

  private

  def controversy_score(pair_hash)
    percentages = Vote.pair_stats(pair_hash)
    return 0 if percentages.empty?

    # Calculate how close to 50/50 the split is (0-100, where 100 is perfect 50/50)
    values = percentages.values
    return 0 if values.length != 2

    deviation = (values[0] - 50).abs
    100 - deviation
  end

  def generate_pair_hash(option1, option2)
    [ option1.id, option2.id ].sort.join("-")
  end
end
