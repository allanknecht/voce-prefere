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

  # CSS width class for the admin statistics bars (no inline style: the CSP forbids it)
  def bar_width_class(value, max)
    pct = max.to_f.positive? ? (value.to_f * 100 / max).round.clamp(0, 100) : 0
    "bar-w-#{pct}"
  end

  def percent_label(part, whole)
    whole.to_i.zero? ? "0%" : "#{(part.to_f * 100 / whole).round(1)}%"
  end
end
