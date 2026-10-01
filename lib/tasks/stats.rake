namespace :stats do
  desc "Fold raw visits/events older than 90 days into daily_stats and delete them (idempotent)"
  task compact: :environment do
    puts "Compacted #{Analytics::Compactor.new.run} day(s)"
  end
end
