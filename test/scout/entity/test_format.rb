require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestEntityFormat < Test::Unit::TestCase
  def test_format
    index = Entity::FormatIndex.new
    index["Ensembl Gene ID"] = "Gene"
    assert_equal "Gene", index["Ensembl Gene ID"]
    assert_equal "Gene", index["Transcription Factor (Ensembl Gene ID)"]

    Entity::FORMATS["Ensembl Gene ID"] = "Gene"
    assert_equal "Ensembl Gene ID", Entity::FORMATS.find("Ensembl Gene ID")
    assert_equal "Ensembl Gene ID", Entity::FORMATS.find("Transcription Factor (Ensembl Gene ID)")

    assert_equal "Gene", Entity::FORMATS["Ensembl Gene ID"]
    assert_equal "Gene", Entity::FORMATS["Transcription Factor (Ensembl Gene ID)"]
  end
end

