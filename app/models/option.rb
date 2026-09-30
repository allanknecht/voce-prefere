class Option < ApplicationRecord
  has_many :votes, dependent: :destroy

  validates :text, presence: true, length: { maximum: 120 }
  validates :status, presence: true, inclusion: { in: %w[pending approved rejected] }
  validates :report_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :approved, -> { where(status: "approved") }
  scope :pending, -> { where(status: "pending") }
  scope :reported, -> { where("report_count >= ?", 3) }

  before_validation :set_defaults, on: :create

  # Any change (approve, reject, report, new submission, ...) drops the cached lists built
  # from approved options (see PairGenerator), so moderation shows up immediately.
  after_commit { PairGenerator.expire_caches! }

  def approve!
    update!(status: "approved", report_count: 0)
  end

  def reject!
    update!(status: "rejected")
  end

  def report!
    increment!(:report_count)
    update!(status: "pending") if report_count >= 3 && status == "approved"
  end

  private

  def set_defaults
    self.status ||= "pending"
    self.report_count ||= 0
    self.is_seed ||= false
  end
end
