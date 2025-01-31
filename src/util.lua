-- Utilities
local util = {}

local cast
function cast(tableOfParams, typeName)
   -- Some nice aliases
   if typeName == "float" then typeName = "torch.FloatTensor" end
   if typeName == "double" then typeName = "torch.DoubleTensor" end
   if typeName == "cuda" then typeName = "torch.CudaTensor" end

   -- Recursively cast
   local out = {}
   for key,value in pairs(tableOfParams) do
      if torch.isTensor(value) then
         out[key] = value:type(typeName)
      elseif type(value) == "table" then
         out[key] = cast(value,typeName)
      else
         out[key] = value
      end
   end
   return out
end

util.cast = cast

function util.oneHot(labels, n)
   --[[
   Assume labels is a 1D tensor of contiguous class IDs, starting at 1.
   Turn it into a 2D tensor of size labels:size(1) x nUniqueLabels

   This is a pretty dumb function, assumes your labels are nice.
   ]]
   local n = n or labels:max()
   local nLabels = labels:size(1)
   local out = labels.new(nLabels, n):fill(0)
   for i=1,nLabels do
      out[i][labels[i]] = 1.0
   end
   return out
end

-- Helpers:
function util.logSumExp(array)
   local max = torch.max(array)
   return torch.log(torch.sum(torch.exp(array-max))) + max
end

function util.logSoftMax(array)
   return array - util.logSumExp(array)
end

function util.sigmoid(array)
   return torch.pow(torch.exp(-array) + 1, -1)
end

function util.sigmoidInPlace(output, input)
   output:resizeAs(input):copy(input)
   output:mul(-1):exp():add(1):pow(-1)
   return output
end

function util.lookup(tble, indexes)
   local indexSize = torch.size(indexes):totable()
   local rows = torch.index(tble, 1, torch.long(torch.view(indexes, -1)))
   table.insert(indexSize, torch.size(rows, 2))
   return torch.view(rows, table.unpack(indexSize))
end

function util.dropout(state, dropout)
   dropout = dropout or 0
   local keep = 1 - dropout
   local s = util.newTensorLike(state)
   local keep = torch.mul(torch.bernoulli(s, keep), 1 / keep)
   return torch.cmul(state, keep)
end

function util.setNotEqual(a, b, c, v)
   local mask = torch.ne(a, b)
   local copy = v:clone()
   copy[mask] = 0
   return copy
end

function util.setNotEqualInPlace(o, a, b, c, v)
   local mask = torch.ne(a, b)
   local copy = o:copy(v)
   copy[mask] = 0
   return copy
end

function util.newTensorLike(a)
   return a.new(a:size())
end

function util.newTensorLikeInPlace(o, a)
   return o
end

function util.fillSameSizeAs(a, b)
   return a.new(a:size()):fill(b)
end

function util.fillSameSizeAsInPlace(o, a, b)
   return o:fill(b)
end

function util.zerosLike(a, b)
   b = b or a
   return a.new(b:size()):zero()
end

function util.zerosLikeInPlace(o, a, b)
   return o:zero()
end

function util.narrowCopy(a, dim, index, size)
   return a:narrow(dim, index, size):clone()
end

function util.narrowCopyInPlace(a, dim, index, size)
   return o:copy(a:narrow(dim, index, size))
end

function util.selectCopy(o, a, dim, index)
   return a:select(dim, index):clone()
end

function util.selectCopyInPlace(o, a, dim, index)
   return o:copy(a:select(dim, index))
end

function util.selectSliceCopy(g, x, dim, index)
   local out = g.new(x:size()):zero()
   local slice = out:select(dim,index)
   slice:copy(g)
   return out
end

function util.selectSliceCopyInPlace(o, g, x, dim, index)
   local out = o:zero()
   local slice = out:select(dim,index)
   slice:copy(g)
   return out
end

function util.narrowSliceCopy(g, x, dim, index, size)
   local out = g.new(x:size()):zero()
   local slice = out:narrow(dim,index,size)
   slice:copy(g)
   return out
end

function util.narrowSliceCopyInPlace(o, g, x, dim, index, size)
   local out = o:zero()
   local slice = out:narrow(dim,index,size)
   slice:copy(g)
   return out
end

function util.indexAdd(g, x, dim, index)
   local out = util.zerosLike(g, x)
   for i=1,torch.size(index, 1) do
      torch.narrow(out,dim,index[i],1):add(torch.narrow(g,dim,i,1))
   end
   return out
end

function util.indexAddInPlace(o, g, x, dim, index)
   local out = o:zero()
   for i=1,torch.size(index, 1) do
      torch.narrow(out,dim,index[i],1):add(torch.narrow(g,dim,i,1))
   end
   return out
end

function util.catTable(g, x, y)
   dim = y or torch.nDimension(x[1])
   local ln=#x
   local out = {}
   local currentIndex = 1
   for i=1,ln do
      local thisSize = torch.size(x[i], dim)
      out[i] = torch.narrow(g,dim,currentIndex,thisSize)
      currentIndex = currentIndex + thisSize
   end
   return out
end

function util.makeContiguous(g)
   if not g:isContiguous() then
      g = g:contiguous()
   end
   return g
end

function util.equals(a, b)
   return a == b
end

function util.defaultBool(b, db)
   if b == nil then
      return db
   end
   return b
end

function util.sortedFlatten(tbl, flat, noRecurse)
   flat = flat or { }
   if type(tbl) == "table" then
      local keys = { }
      for k, v in pairs(tbl) do
         keys[#keys + 1] = k
      end
      local ok = pcall(function()
         return table.sort(keys)
      end)
      if not ok then
         table.sort(keys, function(a, b)
            return tostring(a) < tostring(b)
         end)
      end
      for i = 1, #keys do
         local val = tbl[keys[i]]
         if type(val) == "table" and not noRecurse then
            util.sortedFlatten(val, flat)
         else
            flat[#flat + 1] = val
         end
      end
      return flat
   else
      flat[#flat + 1] = tbl
   end
   return flat
end

function util.deepCopy(tbl)
   if type(tbl) == "table" then
      local copy = { }
      for k, v in pairs(tbl) do
         if type(v) == "table" then
            copy[k] = util.deepCopy(v)
         else
            copy[k] = v
         end
      end
      return copy
   else
      return tbl
   end
end

return util
