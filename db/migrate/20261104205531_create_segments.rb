class CreateSegments < ActiveRecord::Migration[8.1]
  def change
    create_table :segments do |t|
      t.string :name, null: false
      t.jsonb :rules, null: false
      t.integer :last_count
      t.timestamps
    end
  end
end
