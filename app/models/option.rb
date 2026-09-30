class Option < ApplicationRecord
  has_many :votes, dependent: :destroy

  validates :text, presence: true, length: { maximum: 120 }
  validates :status, presence: true, inclusion: { in: %w[pending approved rejected] }
  validates :category, presence: true, inclusion: { in: OptionClassifier::CATEGORIES }
  validates :report_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :approved, -> { where(status: "approved") }
  scope :pending, -> { where(status: "pending") }
  scope :in_review, -> { where(needs_review: true) }
  CATEGORY_FILTERS = { "boas" => "good", "ruins" => "bad" }.freeze
  CATEGORY_LABELS = { "good" => "Boa", "bad" => "Ruim" }.freeze
  # Off air after this many reports: back into the review queue.
  REPORT_THRESHOLD = 3

  STATUS_FILTERS = { "aprovadas" => "approved", "pendentes" => "pending", "rejeitadas" => "rejected" }.freeze

  scope :reported, -> { where("report_count >= ?", REPORT_THRESHOLD) }

  before_validation :set_defaults, on: :create
  before_validation :guess_category, on: :create

  # Admin edits (save(context: :admin_edit)) must not duplicate another option's text.
  validate :text_not_taken_by_another_option, on: :admin_edit

  # Every deletion path (admin delete, Reprovar, `destroy`, ...) keeps the text in
  # `deleted_options`, inside the same transaction as the delete. `deletion_reason` defaults to "manual".
  attr_writer :deletion_reason
  before_destroy { DeletedOption.record!(self, reason: @deletion_reason || "manual") }

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
  def self.admin_ids(status: nil, query: nil, category: nil)
    scope = STATUS_FILTERS.key?(status) ? where(status: STATUS_FILTERS[status]) : all
    scope = scope.where(category: CATEGORY_FILTERS[category]) if CATEGORY_FILTERS.key?(category)
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

  # Deletes the option and everything hanging off it, atomically, and logs its text in
  # `deleted_options` (reason: "manual" or "reprovada"). (Reports are just the report_count
  # column of the option, so they go with the row.)
  def destroy_with_votes!(reason: "manual")
    self.deletion_reason = reason
    transaction do
      related_votes.delete_all
      destroy!
    end
  end

  # "Aprovar" in the review queue: stays on air, leaves the queue, reports are forgotten.
  def approve!
    update!(status: "approved", needs_review: false, report_count: 0)
  end

  # "Reprovar": the option is deleted for good, with its votes (also votes of pairs that contain
  # it), and its text is logged in `deleted_options` with reason "reprovada".
  def reject!
    destroy_with_votes!(reason: "reprovada")
  end

  # A public report. From REPORT_THRESHOLD reports on, the option goes off air and back into the
  # review queue until the admin decides (Aprovar resets the count).
  def report!
    increment!(:report_count)
    return unless report_count >= REPORT_THRESHOLD && status == "approved"

    update!(status: "pending", needs_review: true)
  end

  private

  def text_not_taken_by_another_option
    key = self.class.sort_key(text)
    return if key.blank?

    taken = self.class.where.not(id: id).pluck(:text).any? { |other| self.class.sort_key(other) == key }
    errors.add(:text, "já existe em outra opção") if taken
  end

  def guess_category
    self.category = OptionClassifier.call(text) if category.blank?
  end

  def set_defaults
    self.status ||= "pending"
    self.report_count ||= 0
    self.is_seed ||= false
  end
end
