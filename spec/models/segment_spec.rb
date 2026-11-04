require "rails_helper"

RSpec.describe Segment do
  let(:rules) { ClickhouseFixtures::SEGMENTS[:season_lapsed_30_days] }

  it "is valid with a name and valid rules" do
    expect(described_class.new(name: "Lapsed season pass", rules: rules)).to be_valid
  end

  it "needs a name" do
    segment = described_class.new(name: "", rules: rules)

    expect(segment).not_to be_valid
    expect(segment.errors[:name]).to include("can't be blank")
  end

  it "rejects rules the validator rejects" do
    segment = described_class.new(name: "Bad", rules: { "match" => "all", "rules" => [ { "type" => "purchase" } ] })

    expect(segment).not_to be_valid
    expect(segment.errors[:rules]).to include(/type must be one of/)
  end

  it "stores the rules as JSON and reads them back" do
    segment = described_class.create!(name: "Lapsed season pass", rules: rules)

    expect(described_class.find(segment.id).rules).to eq(rules)
  end
end
