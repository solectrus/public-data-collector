# What the bucket holds of one field already: the time of its oldest
# point, and the time of its newest point before today. `newest` is nil
# when the field has points from today on alone.
Extent = Data.define(:oldest, :newest)
