class CreateAccessAttempts < ActiveRecord::Migration[7.2]
  def change
    create_table :access_attempts do |t|
      t.string :key, null: false
      t.datetime :created_at, null: false
    end
    add_index :access_attempts, [ :key, :created_at ]
  end
end
