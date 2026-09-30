# Append-only log of the text of options removed by the admin (manual delete) or rejected
# ("Reprovar"). Deliberately has no IP / author / vote data: see the migration.
class DeletedOption < ApplicationRecord
  enum :reason, { manual: "manual", reprovada: "reprovada" }, validate: true

  validates :text, presence: true
  validates :deleted_at, presence: true

  before_validation { self.deleted_at ||= Time.current }

  scope :recent_first, -> { order(deleted_at: :desc, id: :desc) }

  # Copies only the text and the category of the option.
  def self.record!(option, reason:)
    create!(text: option.text, category: option.category, reason: reason)
  end
end
