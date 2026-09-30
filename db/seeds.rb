# Seed data: ~20 harmless, funny options for testing
# All marked as seed data and pre-approved

seed_options = [
  "Ter super velocidade",
  "Ter super força",
  "Poder voar",
  "Ser invisível",
  "Comer pizza todo dia sem engordar",
  "Nunca mais ter que dormir",
  "Poder falar com animais",
  "Ler mentes",
  "Viver em um mundo sem mosquitos",
  "Viver em um mundo sem trânsito",
  "Ter WiFi perfeito em qualquer lugar",
  "Bateria do celular infinita",
  "Sempre acordar descansado",
  "Nunca mais sentir calor",
  "Nunca mais sentir frio",
  "Chocolate que faz bem pra saúde",
  "Poder teletransportar",
  "Voltar no tempo só pra ontem",
  "Entender todos os idiomas",
  "Tocar qualquer instrumento perfeitamente",
  "Ter um cachorro que vive 100 anos",
  "Ter um gato que vive 100 anos"
]

seed_options.each do |text|
  Option.find_or_create_by!(text: text) do |option|
    option.status = "approved"
    option.category = OptionClassifier.call(text)
    option.is_seed = true
  end
end

puts "✓ Criadas #{seed_options.length} opções de seed"
