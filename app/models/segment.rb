# A saved segment: a name plus the rules that define who is in it.
# Stored in PostgreSQL. The guests it matches live in ClickHouse.
class Segment < ApplicationRecord
  validates :name, presence: true, length: { maximum: 100 }
  validate :rules_are_valid

  private

  def rules_are_valid
    validator = SegmentRules::Validator.new(rules)
    validator.errors.each { |message| errors.add(:rules, message) } unless validator.valid?
  end
end
