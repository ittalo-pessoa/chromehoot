class CreateChromehoot < ActiveRecord::Migration[7.2]
  def change
    create_table :users do |t|
      t.string :name, null: false
      t.string :email, null: false
      t.string :password_digest, null: false
      t.timestamps
    end
    add_index :users, :email, unique: true
    add_check_constraint :users, 'email = lower(trim(email))', name: 'normalized_email'
    create_table :quizzes do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false
      t.text :description
      t.string :subject, null: false
      t.datetime :archived_at
      t.timestamps
    end
    create_table :questions do |t|
      t.references :quiz, null: false, foreign_key: true
      t.text :statement, null: false
      t.integer :position, null: false
      t.integer :time_limit_seconds, null: false, default: 30
      t.timestamps
    end
    create_table :choices do |t|
      t.references :question, null: false, foreign_key: true
      t.text :text, null: false
      t.boolean :correct, null: false, default: false
      t.integer :position, null: false
    end
    create_table :game_sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :quiz, null: false, foreign_key: true
      t.string :join_code, limit: 6, null: false
      t.string :status, null: false, default: 'waiting'
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end
    add_index :game_sessions, :join_code, unique: true
    add_check_constraint :game_sessions, "join_code ~ '^[0-9]{6}$'", name: 'six_digit_code'
    add_check_constraint :game_sessions, "status IN ('waiting','running','finished','cancelled')", name: 'game_status'
    create_table :session_questions do |t|
      t.references :game_session, null: false, foreign_key: true
      t.text :statement, null: false
      t.integer :position, null: false
      t.integer :time_limit_seconds, null: false
    end
    create_table :session_choices do |t|
      t.references :session_question, null: false, foreign_key: true
      t.text :text, null: false
      t.boolean :correct, null: false
      t.integer :position, null: false
    end
    create_table :participants do |t|
      t.references :game_session, null: false, foreign_key: true
      t.string :nickname, null: false
      t.string :normalized_nickname, null: false
      t.string :credential_digest, null: false
      t.datetime :removed_at
      t.timestamps
    end
    add_index :participants, [ :game_session_id, :normalized_nickname ], unique: true, name: 'unique_nickname'
    add_index :participants, :credential_digest, unique: true
    create_table :rounds do |t|
      t.references :game_session, null: false, foreign_key: true
      t.references :session_question, null: false, foreign_key: true, index: { unique: true }
      t.string :status, null: false, default: 'pending'
      t.datetime :opened_at
      t.datetime :closes_at
      t.datetime :closed_at
    end
    add_index :rounds, :game_session_id, unique: true, where: "status = 'open'", name: 'one_open_round'
    add_check_constraint :rounds, "status IN ('pending','open','closed','revealed')", name: 'round_status'
    create_table :answers do |t|
      t.references :round, null: false, foreign_key: true
      t.references :participant, null: false, foreign_key: true
      t.references :session_choice, null: false, foreign_key: true
      t.datetime :received_at, null: false
      t.boolean :correct, null: false
      t.integer :points, null: false
    end
    add_index :answers, [ :round_id, :participant_id ], unique: true
    add_check_constraint :answers, 'points BETWEEN 0 AND 1000', name: 'valid_points'
    { questions: :quiz_id, choices: :question_id, session_questions: :game_session_id, session_choices: :session_question_id }.each do |table, parent|
      add_index table, [ parent, :position ], unique: true
      add_check_constraint table, 'position > 0', name: "#{table}_positive_position"
    end
    [ :questions, :session_questions ].each do |table|
      add_check_constraint table, 'time_limit_seconds BETWEEN 10 AND 180', name: "#{table}_time_limit"
    end
  end
end
