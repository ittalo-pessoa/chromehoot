require "test_helper"

class ConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  teardown do
    # This class commits data so independent PostgreSQL connections can race.
    # Restrict cleanup to the game created by each test.
    if @game
      Answer.where(round_id: @game.rounds.select(:id)).delete_all
      Round.where(game_session_id: @game.id).delete_all
      Participant.where(game_session_id: @game.id).delete_all
      SessionChoice.where(session_question_id: @game.session_questions.select(:id)).delete_all
      SessionQuestion.where(game_session_id: @game.id).delete_all
      quiz = @game.quiz
      @game.delete
      Choice.where(question_id: quiz.questions.select(:id)).delete_all
      Question.where(quiz_id: quiz.id).delete_all
      quiz.delete
      quiz.user.delete
    end
  end

  def race(*jobs)
    ready = Queue.new
    gate = Queue.new
    threads = jobs.map do |job|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          gate.pop
          begin
            job.call
          rescue GameError => e
            e
          end
        end
      end
    end
    jobs.size.times { ready.pop }
    jobs.size.times { gate << true }
    threads.map(&:value)
  end

  test "concurrent duplicate answers persist one score" do
    @game = make_game(count: 1)
    participant = join_game(@game)
    round = open_round(@game)
    choice = round.session_question.session_choices.first
    job = -> { Answers::Submit.call(Participant.find(participant.id), round_id: round.id, choice_id: choice.id) }
    results = race(job, job)
    assert_equal 1, Answer.where(participant: participant).count
    assert_equal results.first.id, results.last.id
    assert_equal results.first.points, Rankings::Build.call(@game).first[:points]
  end

  test "closing and answering serialize with a consistent outcome" do
    @game = make_game(count: 1)
    participant = join_game(@game)
    round = open_round(@game)
    choice = round.session_question.session_choices.first
    results = race(
      -> { Answers::Submit.call(Participant.find(participant.id), round_id: round.id, choice_id: choice.id) },
      -> { Rounds::Close.call(GameSession.find(@game.id), round_id: round.id) }
    )
    assert_equal "closed", round.reload.status
    answer = participant.answers.first
    if results.first.is_a?(GameError)
      assert_nil answer
    else
      assert_equal 1, participant.answers.count
      assert_operator answer.received_at, :<=, round.closed_at
    end
    assert_raises(GameError) { Answers::Submit.call(Participant.find(participant.id), round_id: round.id, choice_id: choice.id) } unless answer
  end
end
