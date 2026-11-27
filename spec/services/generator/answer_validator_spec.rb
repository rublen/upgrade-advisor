require "rails_helper"

RSpec.describe Generator::AnswerValidator do
  subject(:errors) { described_class.new(answer, [ 11, 12 ]).errors }

  let(:item) { { "claim" => "Active Record supports composite primary keys.", "version" => "7.1.0", "kind" => "feature", "chunk_ids" => [ 11 ] } }
  let(:answer) { { "summary" => "Composite primary keys were added.", "items" => [ item ], "covered" => true } }

  it "accepts a valid answer" do
    expect(errors).to be_empty
  end

  it "accepts an answer that is not covered and has no items" do
    answer.merge!("covered" => false, "items" => [])

    expect(errors).to be_empty
  end

  it "accepts citations of several chunks from the context" do
    item["chunk_ids"] = [ 11, 12 ]

    expect(errors).to be_empty
  end

  describe "schema" do
    {
      "a missing key" => ->(answer, _item) { answer.delete("covered") },
      "an extra key" => ->(answer, _item) { answer["confidence"] = 0.9 },
      "items that are null" => ->(answer, _item) { answer["items"] = nil },
      "covered as a string" => ->(answer, _item) { answer["covered"] = "yes" },
      "an item without a claim" => ->(_answer, item) { item.delete("claim") },
      "a kind outside the list" => ->(_answer, item) { item["kind"] = "banana" },
      "a claim without citations" => ->(_answer, item) { item["chunk_ids"] = [] },
      "chunk IDs as strings" => ->(_answer, item) { item["chunk_ids"] = [ "11" ] }
    }.each do |problem, break_answer|
      it "rejects #{problem}" do
        break_answer.call(answer, item)

        expect(errors).not_to be_empty
      end
    end

    it "names the field in the message" do
      item["kind"] = "banana"

      expect(errors).to contain_exactly(a_string_including("/items/0/kind"))
    end
  end

  describe "citations" do
    it "rejects chunk IDs that were not in the context" do
      item["chunk_ids"] = [ 11, 99, 98 ]

      expect(errors).to eq [ "cited chunk IDs not in the context: 99, 98" ]
    end

    it "lists each unknown chunk ID once" do
      answer["items"] = [ item.merge("chunk_ids" => [ 99 ]), item.merge("chunk_ids" => [ 99 ]) ]

      expect(errors).to eq [ "cited chunk IDs not in the context: 99" ]
    end
  end

  describe "coverage" do
    it "rejects items in an answer marked as not covered" do
      answer["covered"] = false

      expect(errors).to eq [ "answer is marked as not covered but has 1 items" ]
    end
  end

  it "reports citation and coverage problems together" do
    answer["covered"] = false
    item["chunk_ids"] = [ 99 ]

    expect(errors).to contain_exactly(
      "cited chunk IDs not in the context: 99",
      "answer is marked as not covered but has 1 items"
    )
  end
end
