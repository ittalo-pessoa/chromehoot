require "test_helper"

class SeedsTest < ActiveSupport::TestCase
  test "demo seed is explicit idempotent and uses an environment password" do
    keys = %w[TEACHER_EMAIL TEACHER_PASSWORD TEACHER_NAME DEMO_SEED]
    original = keys.to_h { |key| [ key, ENV[key] ] }
    ENV["TEACHER_EMAIL"] = "seed-#{SecureRandom.hex(5)}@escola.test"
    ENV["TEACHER_PASSWORD"] = SecureRandom.hex(16)
    ENV["TEACHER_NAME"] = "Professor do seed"
    ENV["DEMO_SEED"] = "1"
    2.times { load Rails.root.join("db/seeds.rb") }
    user = User.find_by!(email: ENV["TEACHER_EMAIL"])
    assert user.authenticate(ENV["TEACHER_PASSWORD"])
    assert_equal 1, user.quizzes.count
    quiz = user.quizzes.first
    assert_equal 5, quiz.questions.count
    assert quiz.publishable?
    assert_equal 15, Choice.where(question_id: quiz.questions.select(:id)).count
  ensure
    original&.each { |key, value| ENV[key] = value }
  end
end
