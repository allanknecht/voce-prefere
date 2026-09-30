# Guesses whether an option is "good" (something people would like to have / do) or "bad"
# (something painful, gross, violent, sexual or otherwise a "lesser evil" dilemma).
# "Você prefere" pairs are only built from options of the SAME category (good vs good,
# bad vs bad), so the guess only has to be decent: the admin can fix it in /admin/options and
# every new option is reviewed in /admin/review.
#
# Purely lexical and accent/case-insensitive; it is conservative: anything that does not match
# a "bad" signal is "good".
class OptionClassifier
  GOOD = "good".freeze
  BAD = "bad".freeze
  CATEGORIES = [ GOOD, BAD ].freeze

  # Whole-word / phrase signals of a bad option (matched on text normalised to lowercase ASCII).
  BAD_PATTERNS = [
    # body / sex / gross
    /\bcu\b/, /\bbunda\b/, /\bpau\b/, /\brola\b/, /\bsexo\b/, /\btransar\b/, /\bestupr\w*/, /\bpelad[oa]s?\b/,
    /\bmerda\b/, /\bbosta\b/, /\bfezes\b/, /\bxixi\b/, /\bcoco\b/, /\bvomit\w*/, /\bcusp\w*/, /\blamber\b/,
    /\bnojo\w*/, /\bfed(or|er|ido)\b/, /\bpodre\b/, /\bmofo\b/, /\blixo\b/, /\bsem tomar banho\b/,
    /\bnunca mais (tomar banho|comer|beber|ver|ouvir|falar|andar|usar|jogar|rir|abracar|beijar)\b/,
    # pain / violence / death
    /\bchut\w+/, /\bprego\b/, /\bunha\b/, /\bagulha\b/, /\barranc\w+/, /\bcortar\b/, /\bqueim\w+/,
    /\bmachuc\w+/, /\bdoer\b/, /\bdor\b/, /\bdolorid\w*/, /\bapanh\w+/, /\bsocar\b/, /\bbater\b/, /\blutar\b/,
    /\bmord\w+/, /\bmatar\b/, /\bmorrer\b/, /\bmorte\b/, /\bsangr\w+/, /\btortur\w+/, /\bveneno\b/, /\bchoque\b/,
    /\bcego\b/, /\bsurdo\b/, /\bdoente\b/, /\bdoenca\b/, /\bfome\b/, /\bperder\b/,
    # animals that scare people
    /\bbarata\w*/, /\bratos?\b/, /\bcobras?\b/, /\baranhas?\b/, /\bmacacos?\b/, /\bescorpi\w+/,
    # dreaded public figures / embarrassing situations
    /\bbolsonaro\b/, /\bpassar vergonha\b/,
    # a duration or a frequency used as a penalty ("por 10 anos", "3x ao dia")
    /\bpor \d+ (anos?|meses|semanas?|dias?)\b/, /\b\d+x ao dia\b/
  ].freeze

  def self.call(text)
    new(text).category
  end

  def initialize(text)
    @text = text.to_s
  end

  def category
    bad? ? BAD : GOOD
  end

  def bad?
    BAD_PATTERNS.any? { |pattern| normalized.match?(pattern) }
  end

  private

  def normalized
    @normalized ||= @text.unicode_normalize(:nfd).gsub(/\p{Mn}/, "").downcase
  end
end
