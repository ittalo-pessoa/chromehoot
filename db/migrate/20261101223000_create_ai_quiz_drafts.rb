class CreateAiQuizDrafts < ActiveRecord::Migration[7.2]
  def change
    create_table :ai_quiz_drafts do |t|
      t.references :user, null: false, foreign_key: true
      t.references :quiz, foreign_key: true
      t.string :topic, null: false
      t.string :subject, null: false
      t.string :grade_level, null: false
      t.string :difficulty, null: false
      t.integer :question_count, null: false
      t.string :status, null: false, default: 'queued'
      t.jsonb :content
      t.text :error_message
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end
    add_index :ai_quiz_drafts, [ :status, :created_at ]
    add_check_constraint :ai_quiz_drafts, "status IN ('queued','processing','ready','failed','imported')", name: 'ai_draft_status'
    add_check_constraint :ai_quiz_drafts, 'question_count BETWEEN 3 AND 5', name: 'ai_question_count'
  end
end
