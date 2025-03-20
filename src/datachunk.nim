import std/[strformat]
import /[api, types, vector, exceptions]

type
  DataChunkBase = object of RootObj
    handle*: duckdbDataChunk
    types: seq[LogicalType]  # only here for lifetime tracking, maybe I can avoid this
    shouldDestroy: bool
  DataChunk* = ref object of DataChunkBase

converter toC*(d: DataChunk): duckdbdatachunk =
  d.handle

converter toBool*(d: DataChunk): bool =
  not isNil(d) or duckdbdatachunkgetsize(d).int > 0

proc `=destroy`(d: DataChunkBase) =
  if d.handle != nil and d.shouldDestroy:
    `=destroy`(d.types)
    duckdb_destroy_datachunk(d.handle.addr)

proc columnCount*(chunk: DataChunk): int =
  return duckdbDataChunkGetColumnCount(chunk.handle).int

proc newDataChunk*(types: seq[DuckType], shouldDestroy: bool = true): DataChunk =
  let columnCount = len(types)
  var logicalTypes = newSeq[LogicalType](columnCount)
  var duckLogicalTypes = newSeq[duckdbLogicalType](columnCount)

  for i, tp in types:
    logicalTypes[i] = newLogicalType(tp)
    duckLogicalTypes[i] = logicalTypes[i].handle

  let
    chunk = duckdb_create_data_chunk(
      cast[ptr duckdb_logical_type](duckLogicalTypes[0].addr), len(types).idx_t
    )

  if chunk == nil:
    raise newException(OperationError, "Failed to create data chunk")

  return DataChunk(handle: chunk, types: logicalTypes, shouldDestroy: shouldDestroy)

proc newDataChunk*(handle: duckdb_data_chunk, shouldDestroy: bool = true): DataChunk =
  let columnCount = duckdbDataChunkGetColumnCount(handle).int
  var types = newSeq[LogicalType](columnCount)

  for i in 0 ..< columnCount:
    let vec = duckdbDataChunkGetVector(handle, i.idx_t)
    let kind = duckdbVectorGetColumnType(vec)
    types[i] = newLogicalType(kind)

  return DataChunk(handle: handle, types: types, shouldDestroy: shouldDestroy)

proc len*(chunk: DataChunk): int =
  result = duckdbDataChunkGetSize(chunk.handle).int

proc `len=`*(chunk: DataChunk, sz: int) =
  duckdbDataChunkSetSize(chunk.handle, sz.idx_t)

template `[]=`*[T: SomeNumber](vec: duckdbVector, i: int, val: T) =
  var raw = duckdbVectorGetData(vec)
  when T is int:
    cast[ptr UncheckedArray[cint]](raw)[i] = cint(val)
  else:
    cast[ptr UncheckedArray[T]](raw)[i] = val

template `[]=`*(vec: duckdbVector, i: int, val: bool) =
  var raw = duckdbVectorGetData(vec)
  cast[ptr UncheckedArray[uint8]](raw)[i] = val.uint8

proc `[]=`*[T](chunk: var DataChunk, colIdx: int, values: seq[T]) =
  if chunk.len != 0 and chunk.len != len(values):
    raise newException(
      ValueError,
      fmt"Chunk size is inconsistent, new size of {len(values)} is different from {chunk.len}",
    )
  elif len(values) > VECTOR_SIZE:
    raise newException(
      ValueError, fmt"Chunk size is bigger than the allowed vector size: {VECTOR_SIZE}"
    )

  var vec = duckdbDataChunkGetVector(chunk, colIdx.idx_t)
  for i, e in values:
    vec[i] = e

  chunk.len = len(values)

proc `[]=`*(vec: duckdbVector, i: int, val: string) =
  duckdbVectorAssignStringElement(vec, i.idx_t, val.cstring)

proc `[]=`*(chunk: var DataChunk, colIdx: int, values: seq[string]) =
  var vec = duckdbDataChunkGetVector(chunk, colIdx.idx_t)
  let kind = newLogicalType(duckdbVectorGetColumnType(vec))
  if newDuckType(kind) != DuckType.Varchar:
    raise newException(ValueError, "Column is not of type VarChar")
  for i, e in values:
    vec[i] = e

  if chunk.len != 0 and chunk.len != len(values):
    raise newException(
      ValueError,
      fmt"Chunk size is inconsistent, new size of {len(values)} is different from {chunk.len}",
    )
  chunk.len = len(values)

proc `[]`*(chunk: DataChunk, colIdx: int): Vector =
  let vec = duckdbDataChunkGetVector(chunk.handle, colIdx.idx_t)
  return newVector(vec, chunk.len)
