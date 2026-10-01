class Vote < ApplicationRecord
  belongs_to :option

  validates :pair_hash, presence: true
  validates :option_id, presence: true

  # Vote counts per option for one pair, in a single grouped query:
  #   { option_id => votes }
  def self.pair_counts(pair_hash)
    where(pair_hash: pair_hash).group(:option_id).count
  end

  def self.percentages_from(counts)
    total = counts.values.sum
    return {} if total.zero?

    counts.transform_values { |count| (count.to_f / total * 100).round(1) }
  end

  # { option_id => percentage } (empty when nobody voted yet)
  def self.pair_stats(pair_hash)
    percentages_from(pair_counts(pair_hash))
  end

  # [percentages, total_votes] with ONE query (instead of a grouped query plus a COUNT).
  def self.pair_summary(pair_hash)
    counts = pair_counts(pair_hash)
    [ percentages_from(counts), counts.values.sum ]
  end

  # ONE query for several pairs: { pair_hash => { option_id => votes } }
  def self.counts_for_pairs(pair_hashes)
    where(pair_hash: pair_hashes).group(:pair_hash, :option_id).count
      .each_with_object(Hash.new { |h, k| h[k] = {} }) { |((hash, option_id), n), acc| acc[hash][option_id] = n }
  end
end
