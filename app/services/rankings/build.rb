module Rankings
  class Build
    def self.call(game, public_only: false)
      answers = Answer.joins(:round).where(rounds: { game_session_id: game.id }).includes(:round).to_a
      answers.select! { |a| a.round.status == "revealed" } if public_only
      grouped = answers.group_by(&:participant_id)
      rows = game.participants.map do |participant|
        items = grouped.fetch(participant.id, [])
        correct = items.select(&:correct?)
        { participant: participant, nickname: participant.nickname, points: items.sum(&:points), correct: correct.size,
          elapsed: correct.sum { |a| ((a.received_at - a.round.opened_at) * 1_000_000).round } }
      end
      rows.sort_by! { |r| [ -r[:points], -r[:correct], r[:elapsed], r[:nickname].downcase ] }
      previous = nil
      rank = 0
      rows.each_with_index do |row, index|
        key = row.values_at(:points, :correct, :elapsed)
        rank = index + 1 unless previous == key
        row[:rank] = rank
        previous = key
      end
      rows
    end
  end
end
