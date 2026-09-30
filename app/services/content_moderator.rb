class ContentModerator
  # Default/example blocklist - harmless examples for development/testing
  # Production should use MODERATION_BLOCKLIST env var with actual terms
  DEFAULT_PROFANITY_LIST = %w[
    palavrao1 palavrao2 termo-explicito
  ].freeze

  # Default/example proper names list - harmless examples for development/testing
  # Production should use MODERATION_NAMES_BLOCKLIST env var with actual names
  DEFAULT_NAMES_LIST = %w[
    exemplo-politico exemplo-marca exemplo-celebridade
  ].freeze

  # Load blocklists from environment variables or use defaults
  def self.profanity_list
    @profanity_list ||= load_list_from_env("MODERATION_BLOCKLIST", DEFAULT_PROFANITY_LIST)
  end

  def self.proper_names_list
    @proper_names_list ||= load_list_from_env("MODERATION_NAMES_BLOCKLIST", DEFAULT_NAMES_LIST)
  end

  def self.load_list_from_env(env_var, default_list)
    env_value = ENV[env_var]
    return default_list if env_value.blank?

    # Support both comma and newline separated lists
    env_value.split(/[,\n]/).map(&:strip).reject(&:blank?).map(&:downcase)
  end

  # Reset cached lists (useful for testing)
  def self.reset_lists!
    @profanity_list = nil
    @proper_names_list = nil
  end

  def self.check(text)
    new(text).check
  end

  def initialize(text)
    @original = text.to_s.strip
    @normalized = normalize_text(@original)
  end

  def check
    {
      approved: approved?,
      reasons: reasons
    }
  end

  def approved?
    reasons.empty?
  end

  def reasons
    @reasons ||= [].tap do |r|
      r << :profanity if has_profanity?
      r << :explicit_content if has_explicit_content?
      r << :proper_names if has_proper_names?
    end
  end

  private

  def normalize_text(text)
    normalized = text.downcase

    # Remove accents
    normalized = normalized.tr(
      "áàâãäéèêëíìîïóòôõöúùûüçñ",
      "aaaaaeeeeiiiiooooouuuucn"
    )

    # Replace leetspeak (common substitutions)
    normalized = normalized.tr("0134567@$", "oieasbtas")

    # Remove all spaces and special chars
    normalized.gsub(/[\s\-_]+/, "")
  end

  def has_profanity?
    # Check normalized text against normalized profanity list
    self.class.profanity_list.any? do |word|
      normalized_word = normalize_text(word)
      @normalized.include?(normalized_word)
    end
  end

  def has_explicit_content?
    # Already covered in profanity list
    false
  end

  # Blocklisted names (MODERATION_NAMES_BLOCKLIST) are the real protection against
  # real people / brands. Two matching modes keep false positives low:
  #   * short names (< 6 chars) only match as whole words ("ana" must not hit "banana");
  #   * longer names also match when spaced out or leetspeak'd ("t e s t b r a n d").
  # On top of that a deliberately narrow heuristic flags what looks like a full
  # person name in the middle of a sentence: two or more consecutive capitalized
  # words ("Votar em João Silva", "Maria da Silva"). A single capitalized word
  # ("Brasil", "Netflix", "Natal") and sentence-initial capitals are fine.
  SQUASH_MIN_LENGTH = 6
  NAME_CONNECTORS = %w[da de do das dos e].freeze
  # Multi-word proper nouns that are not people
  SAFE_CAPITALIZED_RUNS = [
    "sao paulo", "rio de janeiro", "belo horizonte", "porto alegre", "ano novo",
    "papai noel", "dia dos", "copa do mundo", "estados unidos", "nova york",
    "minas gerais", "santa catarina", "espirito santo", "fernando de noronha"
  ].freeze

  def has_proper_names?
    blocklisted_name? || looks_like_full_person_name?
  end

  def blocklisted_name?
    spaced = normalize_spaced(@original)

    self.class.proper_names_list.any? do |name|
      squashed = normalize_text(name)
      next false if squashed.empty?

      spaced.match?(/(?:\A|\s)#{Regexp.escape(normalize_spaced(name))}(?:\s|\z)/) ||
        (squashed.length >= SQUASH_MIN_LENGTH && @normalized.include?(squashed))
    end
  end

  def looks_like_full_person_name?
    words = @original.split(/\s+/)[1..] || []
    words = words.map { |w| w.gsub(/\A[^\p{L}]+|[^\p{L}]+\z/, "") }.reject(&:empty?)

    run = []
    flush = lambda do
      while run.any? && NAME_CONNECTORS.include?(run.last.downcase)
        run.pop
      end
      capitalized = run.reject { |w| NAME_CONNECTORS.include?(w.downcase) }
      flagged = capitalized.length >= 2 && !SAFE_CAPITALIZED_RUNS.any? { |safe| normalize_spaced(run.join(" ")).include?(safe) }
      run = []
      flagged
    end

    words.each do |word|
      if capitalized_word?(word)
        run << word
      elsif run.any? && NAME_CONNECTORS.include?(word.downcase)
        run << word
      else
        return true if flush.call
      end
    end
    flush.call
  end

  def capitalized_word?(word)
    word.match?(/\A\p{Lu}\p{Ll}+\z/)
  end

  # Lowercase, accents removed, leetspeak undone, words kept apart
  def normalize_spaced(text)
    text.to_s.downcase
        .tr("áàâãäéèêëíìîïóòôõöúùûüçñ", "aaaaaeeeeiiiiooooouuuucn")
        .tr("0134567@$", "oieasbtas")
        .gsub(/[^a-z\s]+/, " ")
        .squeeze(" ")
        .strip
  end
end
