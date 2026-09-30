# Append-only log of the text of options the admin deleted ("excluída manualmente" from
# /admin/options, "excluída na fila" from the review queue). Deliberately has no IP / author /
# vote data: see the migration.
class DeletedOption < ApplicationRecord
  # Stored values are kept as they are (no migration): `reprovada` = deleted from the review queue.
  enum :reason, { manual: "manual", reprovada: "reprovada" }, validate: true
  REASON_LABELS = { "manual" => "Excluída manualmente", "reprovada" => "Excluída na fila" }.freeze

  validates :text, presence: true
  validates :deleted_at, presence: true

  before_validation { self.deleted_at ||= Time.current }

  scope :recent_first, -> { order(deleted_at: :desc, id: :desc) }

  def reason_label
    REASON_LABELS.fetch(reason, reason.to_s)
  end

  # Copies only the text and the category of the option.
  def self.record!(option, reason:)
    create!(text: option.text, category: option.category, reason: reason)
  end
end
