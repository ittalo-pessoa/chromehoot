class ExpandAiQuizQuestionCount < ActiveRecord::Migration[7.2]
  def up
    remove_check_constraint :ai_quiz_drafts, name: 'ai_question_count'
    add_check_constraint :ai_quiz_drafts, 'question_count BETWEEN 3 AND 20', name: 'ai_question_count'
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Rascunhos podem conter mais de cinco questões.'
  end
end
