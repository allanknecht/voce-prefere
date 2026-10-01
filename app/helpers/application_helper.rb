module ApplicationHelper
  # "1 voto" / "N votos" (0 is plural in Portuguese): never "1 votos".
  def count_label(count, singular, plural)
    "#{count} #{count.to_i == 1 ? singular : plural}"
  end

  def votes_label(count, suffix = nil)
    [ count_label(count, "voto", "votos"), suffix ].compact.join(" ")
  end

  def reports_label(count)
    count_label(count, "denúncia", "denúncias")
  end
end
