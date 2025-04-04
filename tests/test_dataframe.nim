import unittest2
import std/[tables, sequtils]
import ../src/[dataframe, vector]
import utils

suite "Test Dataframe":
  setup:
    let df =
      newDataFrame({"foo": newVector(@[10, 20]), "bar": newVector(@["a", "b"])}.toTable)

  test "Test dataframe columns":
    check df.columnNames == @["foo", "bar"]

  test "Test dataframe columns accessed by name":
    check df["foo"].valueBigInt == @[10'i64, 20'i64]
    check df["bar"].valueVarchar == @["a", "b"]

  test "Test dataframe access per row basis":
    let row = df.rows.toSeq[1]
    check row[0].valueBigint == 20
    check row[1].valueVarchar == "b"

  test "Test invalid column name":
    ignoreLeak:
      expect ValueError:
        discard df["something that does not exist"]

  test "Test echo the dataframe":
    let output = $df
    check output ==
      """
┌─────┬─────────────┬─────────────┐
│  #  │     foo     │     bar     │
├─────┼─────────────┼─────────────┤
│  0  │     10      │     a       │
│  1  │     20      │     b       │
└─────┴─────────────┴─────────────┘
"""
