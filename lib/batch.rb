# What a provider hands to the writer: the rows of one measurement.
#
# Every row carries its time and its fields as {name => value}. A field
# without a value is left out, because a missing value is not a value of
# zero.
Batch = Data.define(:measurement, :rows)

Batch::Row = Data.define(:time, :fields)
