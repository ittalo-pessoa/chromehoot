require "test_helper"

class AiQuizzesContentTest < ActiveSupport::TestCase
  def content
    { "title" => "Redes locais", "description" => "Revisão", "questions" => 3.times.map { |i| { "statement" => "Questão #{i + 1}", "choices" => [ "Cabo de rede", "Monitor", "Teclado", "Mouse" ], "correct_index" => 0 } } }
  end

  test "validates generated and edited content without accepting arbitrary correctness or count" do
    result = AiQuizzes::Content.call(content, count: 3)
    assert_equal 30, result["questions"].first["time_limit_seconds"]
    form = result.deep_dup
    form["questions"] = form["questions"].each_with_index.to_h { |q, i| [ i.to_s, q.merge("correct_index" => "2", "time_limit_seconds" => "45") ] }
    normalized = AiQuizzes::Content.call(form, count: 3, form: true)
    assert_equal 2, normalized["questions"].first["correct_index"]
    assert_equal 45, normalized["questions"].first["time_limit_seconds"]
    invalid = content
    invalid["questions"][0]["correct_index"] = true
    assert_raises(GameError) { AiQuizzes::Content.call(invalid, count: 3) }
    assert_raises(GameError) { AiQuizzes::Content.call(content, count: 5) }
    invalid = content
    invalid["questions"][0]["choices"][1] = "Cabo de rede"
    assert_raises(GameError) { AiQuizzes::Content.call(invalid, count: 3) }
    invalid = content
    invalid["questions"][0]["statement"] = { "html" => "script" }
    assert_raises(GameError) { AiQuizzes::Content.call(invalid, count: 3) }
    form["questions"]["0"]["time_limit_seconds"] = "30abc"
    assert_raises(GameError) { AiQuizzes::Content.call(form, count: 3, form: true) }
  end
end
