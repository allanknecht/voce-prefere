class Option < ApplicationRecord
  has_many :votes, dependent: :destroy

  validates :text, presence: true, length: { maximum: 120 }
  # `pending` / `rejected` are legacy values of the old moderation; nothing creates them any more
  # (they are kept so existing rows stay valid until the admin approves or deletes them).
  validates :status, presence: true, inclusion: { in: %w[pending approved rejected] }
  validates :category, presence: true, inclusion: { in: OptionClassifier::CATEGORIES }
  validates :report_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :approved, -> { where(status: "approved") }
  scope :in_review, -> { where(needs_review: true) }
  CATEGORY_FILTERS = { "boas" => "good", "ruins" => "bad" }.freeze
  CATEGORY_LABELS = { "good" => "Boa", "bad" => "Ruim" }.freeze

  # Nothing is ever taken off the air automatically: public pages show `approved` options only,
  # and the only way an option stops being approved is an old (pre-#6) state that the admin
  # resolves in the review queue (Aprovar = back on air, Excluir = delete).
  STATUS_FILTERS = { "aprovadas" => "approved", "fora-do-ar" => :off_air }.freeze
  STATUS_LABELS = { "approved" => "No ar" }.freeze

  # Review queue order: reported options first (most reports first), then oldest first.
  scope :review_order, -> { order(report_count: :desc, created_at: :asc, id: :asc) }

  before_validation :set_defaults, on: :create
  before_save :set_text_key
  before_validation :guess_category, on: :create

  # Public submissions: a duplicate (case/accent/space-insensitive) is refused with a friendly
  # message. The UNIQUE index on `text_key` is the race-proof part (see OptionsController).
  validate :text_key_free, on: :create

  # Admin edits (save(context: :admin_edit)) must not duplicate another option's text.
  validate :text_not_taken_by_another_option, on: :admin_edit

  # Every deletion path (manual delete, Excluir in the queue, `destroy`, ...) keeps the text in
  # `deleted_options`, inside the same transaction as the delete. `deletion_reason` defaults to "manual".
  attr_writer :deletion_reason
  before_destroy { DeletedOption.record!(self, reason: @deletion_reason || "manual") }

  # Any change (approve, edit, delete, new submission, ...) drops the cached lists built
  # from approved options (see PairGenerator), so admin decisions show up immediately.
  after_commit { PairGenerator.expire_caches! }

  # Case- and accent-insensitive key ("Ação" == "acao" == "AÇÃO"): used for the alphabetical
  # order, the admin search and the duplicate check. Done in Ruby (not SQL) so that it behaves
  # the same on SQLite and PostgreSQL without extensions (unaccent, ICU collations).
  # Emoji and other symbols are kept as they are.
  def self.sort_key(text)
    text.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, "").downcase.squish
  end

  # true when another option already has this text (same normalised key)
  def self.text_taken?(text, except_id: nil)
    key = sort_key(text)
    return false if key.blank?

    scope = where(text_key: key)
    scope = scope.where.not(id: except_id) if except_id
    scope.exists?
  end

  # Ids of ALL options matching the filters, in alphabetical order.
  #   status: one of STATUS_FILTERS keys ("aprovadas", ...) or blank for all
  #   query:  plain substring, case/accent-insensitive. It is matched literally in Ruby, so
  #           "%" and "_" are ordinary characters (no LIKE wildcards, nothing is interpolated in SQL).
  # The app keeps a small table of short texts, so one `SELECT id, text` per page view is cheap.
  def self.admin_ids(status: nil, query: nil, category: nil)
    scope = all
    scope = STATUS_FILTERS[status] == :off_air ? where.not(status: "approved") : where(status: "approved") if STATUS_FILTERS.key?(status)
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
  # `deleted_options` (reason: "manual", or "reprovada" when deleted from the queue). (Reports are just the report_count
  # column of the option, so they go with the row.)
  def destroy_with_votes!(reason: "manual")
    self.deletion_reason = reason
    transaction do
      related_votes.delete_all
      destroy!
    end
  end

  # "Aprovar" in the review queue: on the air (also for old off-air options), out of the queue,
  # report count back to 0 (so a later report queues it again).
  def approve!
    update!(status: "approved", needs_review: false, report_count: 0)
  end

  # "Excluir" in the queue: deleted for good with its votes (also votes of pairs that contain it),
  # text logged in `deleted_options` (reason "reprovada" is the stored value, shown as
  # "excluída na fila").
  def destroy_from_queue!
    destroy_with_votes!(reason: "reprovada")
  end

  # A public report. NOTHING is taken off the air: the option stays live, the counter goes up
  # and the option (re)enters the review queue, where reported options are shown first.
  # One atomic UPDATE (no lost increments under concurrent reports).
  def report!
    self.class.where(id: id).update_all([ "report_count = report_count + 1, needs_review = ?", true ])
    reload
  end

  private

  # The normalised text behind the UNIQUE index, refreshed whenever the text changes (legacy
  # duplicates keep NULL, see the migration).
  def set_text_key
    self.text_key = self.class.sort_key(text).presence if new_record? || text_changed?
  end

  def text_key_free
    errors.add(:text, "já existe em outra opção") if self.class.text_taken?(text)
  end

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
