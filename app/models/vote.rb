class Vote < ApplicationRecord
  belongs_to :option

  validates :pair_hash, presence: true
  validates :option_id, presence: true

  def self.pair_stats(pair_hash)
    votes = where(pair_hash: pair_hash).group(:option_id).count
    total = votes.values.sum
    return {} if total.zero?

    votes.transform_values { |count| (count.to_f / total * 100).round(1) }
  end
end
