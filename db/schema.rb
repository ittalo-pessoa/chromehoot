# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.2].define(version: 2026_11_01_210100) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "access_attempts", force: :cascade do |t|
    t.string "key", null: false
    t.datetime "created_at", null: false
    t.index ["key", "created_at"], name: "index_access_attempts_on_key_and_created_at"
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "answers", force: :cascade do |t|
    t.bigint "round_id", null: false
    t.bigint "participant_id", null: false
    t.bigint "session_choice_id", null: false
    t.datetime "received_at", null: false
    t.boolean "correct", null: false
    t.integer "points", null: false
    t.index ["participant_id"], name: "index_answers_on_participant_id"
    t.index ["round_id", "participant_id"], name: "index_answers_on_round_id_and_participant_id", unique: true
    t.index ["round_id"], name: "index_answers_on_round_id"
    t.index ["session_choice_id"], name: "index_answers_on_session_choice_id"
    t.check_constraint "points >= 0 AND points <= 1000", name: "valid_points"
  end

  create_table "choices", force: :cascade do |t|
    t.bigint "question_id", null: false
    t.text "text", null: false
    t.boolean "correct", default: false, null: false
    t.integer "position", null: false
    t.index ["question_id", "position"], name: "index_choices_on_question_id_and_position", unique: true
    t.index ["question_id"], name: "index_choices_on_question_id"
    t.check_constraint "\"position\" > 0", name: "choices_positive_position"
  end

  create_table "game_sessions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "quiz_id", null: false
    t.string "join_code", limit: 6, null: false
    t.string "status", default: "waiting", null: false
    t.datetime "started_at"
    t.datetime "finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["join_code"], name: "index_game_sessions_on_join_code", unique: true
    t.index ["quiz_id"], name: "index_game_sessions_on_quiz_id"
    t.index ["user_id"], name: "index_game_sessions_on_user_id"
    t.check_constraint "join_code::text ~ '^[0-9]{6}$'::text", name: "six_digit_code"
    t.check_constraint "status::text = ANY (ARRAY['waiting'::character varying, 'running'::character varying, 'finished'::character varying, 'cancelled'::character varying]::text[])", name: "game_status"
  end

  create_table "participants", force: :cascade do |t|
    t.bigint "game_session_id", null: false
    t.string "nickname", null: false
    t.string "normalized_nickname", null: false
    t.string "credential_digest", null: false
    t.datetime "removed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["credential_digest"], name: "index_participants_on_credential_digest", unique: true
    t.index ["game_session_id", "normalized_nickname"], name: "unique_nickname", unique: true
    t.index ["game_session_id"], name: "index_participants_on_game_session_id"
  end

  create_table "questions", force: :cascade do |t|
    t.bigint "quiz_id", null: false
    t.text "statement", null: false
    t.integer "position", null: false
    t.integer "time_limit_seconds", default: 30, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["quiz_id", "position"], name: "index_questions_on_quiz_id_and_position", unique: true
    t.index ["quiz_id"], name: "index_questions_on_quiz_id"
    t.check_constraint "\"position\" > 0", name: "questions_positive_position"
    t.check_constraint "time_limit_seconds >= 10 AND time_limit_seconds <= 180", name: "questions_time_limit"
  end

  create_table "quizzes", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "title", null: false
    t.text "description"
    t.string "subject", null: false
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_quizzes_on_user_id"
  end

  create_table "rounds", force: :cascade do |t|
    t.bigint "game_session_id", null: false
    t.bigint "session_question_id", null: false
    t.string "status", default: "pending", null: false
    t.datetime "opened_at"
    t.datetime "closes_at"
    t.datetime "closed_at"
    t.index ["game_session_id"], name: "index_rounds_on_game_session_id"
    t.index ["game_session_id"], name: "one_open_round", unique: true, where: "((status)::text = 'open'::text)"
    t.index ["session_question_id"], name: "index_rounds_on_session_question_id", unique: true
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'open'::character varying, 'closed'::character varying, 'revealed'::character varying]::text[])", name: "round_status"
  end

  create_table "session_choices", force: :cascade do |t|
    t.bigint "session_question_id", null: false
    t.text "text", null: false
    t.boolean "correct", null: false
    t.integer "position", null: false
    t.index ["session_question_id", "position"], name: "index_session_choices_on_session_question_id_and_position", unique: true
    t.index ["session_question_id"], name: "index_session_choices_on_session_question_id"
    t.check_constraint "\"position\" > 0", name: "session_choices_positive_position"
  end

  create_table "session_questions", force: :cascade do |t|
    t.bigint "game_session_id", null: false
    t.text "statement", null: false
    t.integer "position", null: false
    t.integer "time_limit_seconds", null: false
    t.index ["game_session_id", "position"], name: "index_session_questions_on_game_session_id_and_position", unique: true
    t.index ["game_session_id"], name: "index_session_questions_on_game_session_id"
    t.check_constraint "\"position\" > 0", name: "session_questions_positive_position"
    t.check_constraint "time_limit_seconds >= 10 AND time_limit_seconds <= 180", name: "session_questions_time_limit"
  end

  create_table "users", force: :cascade do |t|
    t.string "name", null: false
    t.string "email", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.check_constraint "email::text = lower(btrim(email::text))", name: "normalized_email"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "answers", "participants"
  add_foreign_key "answers", "rounds"
  add_foreign_key "answers", "session_choices"
  add_foreign_key "choices", "questions"
  add_foreign_key "game_sessions", "quizzes"
  add_foreign_key "game_sessions", "users"
  add_foreign_key "participants", "game_sessions"
  add_foreign_key "questions", "quizzes"
  add_foreign_key "quizzes", "users"
  add_foreign_key "rounds", "game_sessions"
  add_foreign_key "rounds", "session_questions"
  add_foreign_key "session_choices", "session_questions"
  add_foreign_key "session_questions", "game_sessions"
end
