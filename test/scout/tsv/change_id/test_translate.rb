require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/tsv'

class TestTSVTranslate < Test::Unit::TestCase
  def test_marriage_index
    marriages = datadir_test.person.marriages.tsv
    identifiers = datadir_test.person.identifiers.tsv
    index = TSV.translation_index [marriages, identifiers], "Husband (ID)", "Husband (Name)"
    assert_equal 'Miguel', index["001"]
  end

  def test_translate_marriages
    marriages = datadir_test.person.marriages.tsv
    marriages = marriages.translate "Husband (ID)", "Husband (Name)"
    marriages = marriages.translate "Wife (ID)", "Wife (Name)"
    assert_equal "Cleia", marriages["Miguel"]["Wife"]
  end


  def test_translation_path
    file_paths = {
      :file1 => %w(A B C),
      :file2 => %w(Y Z A),
      :file3 => %w(Y X),
      :file4 => %w(X R),
      :file5 => %w(A R),
    }

    assert_equal [:file1], TSV.translation_path(file_paths, "C", "A")
    assert_equal [:file1, :file2], TSV.translation_path(file_paths, "B", "Y")
    assert_equal [:file1, :file2, :file3], TSV.translation_path(file_paths, "B", "X")
    assert_equal [:file1, :file5], TSV.translation_path(file_paths, "B", "R")
  end

  def test_translation_index
    f1=<<-EOF
#: :sep=' '
#A B C
a b c
aa bb cc
    EOF

    f2=<<-EOF
#: :sep=' '
#Y Z A
y z a
yy zz aa
    EOF

    f3=<<-EOF
#: :sep=' '
#Y X
y x
yy xx
    EOF

    TmpFile.with_file(f1) do |tf1|
      TmpFile.with_file(f2) do |tf2|
        TmpFile.with_file(f3) do |tf3|
          index = TSV.translation_index([tf1, tf2, tf3], 'A', 'X')
          assert_equal 'x', index['a']
          assert_equal 'xx', index['aa']

          index = TSV.translation_index([tf1, TSV.open(tf2), tf3], 'A', 'X')
          assert_equal 'x', index['a']
          assert_equal 'xx', index['aa']

          index = TSV.translation_index([tf1, TSV.open(tf2), tf3], 'C', 'Y')
          assert_equal 'y', index['c']
          assert_equal 'yy', index['cc']

          index = TSV.translation_index([tf1, TSV.open(tf2), tf3], 'Z', 'Y')
          assert_equal 'y', index['z']
          assert_equal 'yy', index['zz']

          index = TSV.translation_index([tf1, tf2, tf3], 'X', 'A')
          assert_equal 'a', index['x']
          assert_equal 'aa', index['xx']
        end
      end
    end
  end

  def test_translate

    f1=<<-EOF
#: :sep=' '
#A B C
a b c
aa bb cc
    EOF

    identifiers=<<-EOF
#: :sep=' '
#A X
a x
aa xx
    EOF

    TmpFile.with_file(f1) do |tf1|
      TmpFile.with_file(identifiers) do |ti|
        tsv = TSV.open tf1, :identifiers => ti

        assert TSV.translate(tsv, tsv.key_field, "X").include? "x"
      end
    end
  end

  def test_translate_two_files

    f1=<<-EOF
#: :sep=' '
#A B C
a b c
aa bb cc
    EOF

    identifiers1=<<-EOF
#: :sep=' '
#Y Z A
y z a
yy zz aa
    EOF

    identifiers2=<<-EOF
#: :sep=' '
#Y X
y x
yy xx
    EOF

    TmpFile.with_file(f1) do |tf1|
      TmpFile.with_file(identifiers1) do |ti1|
        TmpFile.with_file(identifiers2) do |ti2|
          tsv = TSV.open tf1, :identifiers => [ti1, ti2]

          assert TSV.translate(tsv, tsv.key_field, "X").include? "x"
        end
      end
    end
  end
end

