class Option < ApplicationRecord
  has_many :votes, dependent: :destroy

  validates :text, presence: true, length: { maximum: 120 }
  validates :status, presence: true, inclusion: { in: %w[pending approved rejected] }
  validates :report_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :approved, -> { where(status: "approved") }
  scope :pending, -> { where(status: "pending") }
  STATUS_FILTERS = { "aprovadas" => "approved", "pendentes" => "pending", "rejeitadas" => "rejected" }.freeze

  scope :reported, -> { where("report_count >= ?", 3) }

  before_validation :set_defaults, on: :create

  # Admin edits (save(context: :admin_edit)) must not duplicate another option's text.
  validate :text_not_taken_by_another_option, on: :admin_edit

  # Any change (approve, reject, report, new submission, ...) drops the cached lists built
  # from approved options (see PairGenerator), so moderation shows up immediately.
  after_commit { PairGenerator.expire_caches! }

  # Case- and accent-insensitive key ("Ação" == "acao" == "AÇÃO"): used for the alphabetical
  # order, the admin search and the duplicate check. Done in Ruby (not SQL) so that it behaves
  # the same on SQLite and PostgreSQL without extensions (unaccent, ICU collations).
  # Emoji and other symbols are kept as they are.
  def self.sort_key(text)
    text.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, "").downcase.squish
  end

  # Ids of ALL options matching the filters, in alphabetical order.
  #   status: one of STATUS_FILTERS keys ("aprovadas", ...) or blank for all
  #   query:  plain substring, case/accent-insensitive. It is matched literally in Ruby, so
  #           "%" and "_" are ordinary characters (no LIKE wildcards, nothing is interpolated in SQL).
  # The app keeps a small table of short texts, so one `SELECT id, text` per page view is cheap.
  def self.admin_ids(status: nil, query: nil)
    scope = STATUS_FILTERS.key?(status) ? where(status: STATUS_FILTERS[status]) : all
    needle = sort_key(query)
    rows = scope.pluck(:id, :text).map { |id, text| [ id, text, sort_key(text) ] }
    rows = rows.select { |_, _, key| key.include?(needle) } if needle.present?
    rows.sort_by { |id, text, key| [ key, text, id ] }.map(&:first)
  end

  # Votes that die with this option: its own votes plus every vote cast on a pair that contains
  # it ("a-b" pair_hash), which would otherwise point to a pair that no longer exists.
  def related_votes
    Vote.where(option_id: id)
        .or(Vote.where("pair_hash LIKE ?", "#{id}-%")) # id is an integer: no LIKE wildcards in it
        .or(Vote.where("pair_hash LIKE ?", "%-#{id}"))
  end

  # Deletes the option and everything hanging off it, atomically. (Reports are just the
  # report_count column of the option, so they go with the row.)
  def destroy_with_votes!
    transaction do
      related_votes.delete_all
      destroy!
    end
  end

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

  def text_not_taken_by_another_option
    key = self.class.sort_key(text)
    return if key.blank?

    taken = self.class.where.not(id: id).pluck(:text).any? { |other| self.class.sort_key(other) == key }
    errors.add(:text, "já existe em outra opção") if taken
  end

  def set_defaults
    self.status ||= "pending"
    self.report_count ||= 0
    self.is_seed ||= false
  end
end
