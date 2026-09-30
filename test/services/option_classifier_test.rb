require "test_helper"

class OptionClassifierTest < ActiveSupport::TestCase
  GOOD = [
    "Ter super velocidade", "Poder voar", "Ser invisível", "Comer pizza todo dia sem engordar", "Nunca mais ter que dormir",
    "Viver em um mundo sem mosquitos", "Ter WiFi perfeito em qualquer lugar", "Chocolate que faz bem pra saúde",
    "Ter um cachorro que vive 100 anos", "Tocar qualquer instrumento perfeitamente", "Sempre acordar descansado"
  ].freeze

  BAD = [
    "Dar o cu para o Bolsonaro 3x ao dia por 1 semana", "Chutar a parede com um prego debaixo da unha",
    "Lutar com 5 macacos cada vez que entrar num carro", "Comer batata todo dia por 10 anos no café da manhã",
    "Nunca mais tomar banho", "Ser picado por uma cobra", "Ficar cego"
  ].freeze

  test "the seed options and typical good ones are good" do
    GOOD.each { |text| assert_equal "good", OptionClassifier.call(text), text }
  end

  test "painful, gross, violent or penalty-style options are bad" do
    BAD.each { |text| assert_equal "bad", OptionClassifier.call(text), text }
  end

  test "is case and accent insensitive, and matches whole words only" do
    assert_equal "bad", OptionClassifier.call("CHUTAR A PAREDE")
    assert_equal "good", OptionClassifier.call("Ter um cupcake") # 'cu' inside a word is not the word
    assert_equal "good", OptionClassifier.call("")
  end

  test "new options get a guessed category; an explicit one is kept" do
    assert_equal "bad", Option.create!(text: "Chutar a parede", status: "approved").category
    assert_equal "good", Option.create!(text: "Poder voar alto", status: "approved").category
    assert_equal "bad", Option.create!(text: "Ter asas gigantes", status: "approved", category: "bad").category
    assert_not Option.new(text: "x", status: "approved", category: "meh").valid?
  end
end
