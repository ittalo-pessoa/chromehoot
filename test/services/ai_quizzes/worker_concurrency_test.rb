require "test_helper"

class AiWorkerConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "two independent workers cannot generate at the same time" do
    user = User.create!(name: "Teste IA", email: "ai-worker-#{SecureRandom.hex(5)}@escola.test", password: SecureRandom.hex(16))
    draft = user.ai_quiz_drafts.create!(topic: "Hardware", subject: "Informática", grade_level: "Ensino Médio", difficulty: "easy", question_count: 3)
    entered = Queue.new
    release = Queue.new
    client = Object.new
    client.define_singleton_method(:generate) do |_draft|
      entered << true
      release.pop
      { "title" => "Hardware", "description" => "", "questions" => 3.times.map { |i| { "statement" => "Enunciado #{i + 1}", "choices" => %w[Teclado Monitor Mouse Cabo], "correct_index" => 0 } } }
    end
    first = Thread.new { AiQuizzes::ProcessNext.call(client: client) }
    Timeout.timeout(5) { entered.pop }
    assert_equal "processing", draft.reload.status
    assert_not AiQuizzes::ProcessNext.call(client: client)
    assert_equal "processing", draft.reload.status
    release << true
    assert Timeout.timeout(5) { first.value }
    assert_equal "ready", draft.reload.status
  ensure
    release << true if release
    first&.join(5)
    AiQuizDraft.where(user_id: user.id).delete_all if user
    user&.delete
  end
end
