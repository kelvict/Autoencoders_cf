
-- Load global libraries
require("nn")
require("optim")
require("xlua") 

torch.setdefaulttensortype('torch.FloatTensor') 

require("nnsparse")

dofile("AlgoTools.lua")

dofile("AutoEncoderTrainer.lua")
dofile("LearnU.lua")
dofile("Appender.lua")


----------------------------------------------------------------------
-- parse command-line options
--
cmd = torch.CmdLine()
cmd:text()
cmd:text('Learn SDAE network for collaborative filtering')
cmd:text()
cmd:text('Options')
-- general options:
cmd:option('-file'           , './movieLens-1M.t7'    ,  'The relative path to your data file (torch format)')
cmd:option('-conf'           , "config.template.lua"  , 'The relative path to the lua configuration file')
cmd:option('-seed'           , 0                      , 'The seed')
cmd:option('-meta'           , 0                      , 'use metadata fale = 0, true 1')
cmd:option('-gpu'            , 1                      , 'use gpu')
cmd:option('-save'           , ''                     , "store the final network in an external file")
cmd:text()



local params = cmd:parse(arg)

print("Options: ")
for key, val in pairs(params) do
   print(" - " .. key  .. "  \t : " .. tostring(val))
end


if params.seed > 0 then
   torch.manualSeed(params.seed)
   math.randomseed(params.seed)
else
 torch.manualSeed(torch.initialSeed())
end


--Load configuration
dofile(params.conf)



--Load data
print("loading data...")
local data = torch.load(params.file) 
local train = data.train
local test  = data.test

print(train.U.size .. " Users loaded")
print(train.V.size .. " Items loaded")
print("No Train rating : " .. train.U.noRating)
print("No Test  rating : " .. test.U.noRating)


SHOW_PROGRESS = true
USE_GPU        = params.gpu > 0
USE_META       = params.meta > 0

if USE_GPU then
  print("Loading cunn...")
  require("cunn")
  
  cutorch.setDevice(params.gpu)


  print("Loading data to GPU...")
  local function toGPU(type)
     local _train = train[type]
     local _test  = test [type]
     
     for k, _ in pairs(train[type].data) do
     
         _train.data[k] = _train.data[k]:cuda()
         
         if _train.info.metaDim then
            
            _train.info[k].full       = _train.info[k].full       or torch.Tensor(_train.info.metaDim):zero()
            _train.info[k].fullSparse = _train.info[k].fullSparse or torch.Tensor()

            _train.info[k].full       = _train.info[k].full:cuda()
            _train.info[k].fullSparse = _train.info[k].fullSparse:cuda()
         end
     end
     
     for k, _ in pairs(test[type].data) do

         _test .data[k] = _test .data[k]:cuda()

         if _train.info.metaDim then
           
            if _train.info[k] == nil or _train.info[k].full == nil then 
              _train.info[k] = {}
              _train.info[k].full       = torch.Tensor(_train.info.metaDim):zero()
              _train.info[k].fullSparse = torch.Tensor()
            end

            _train.info[k].full       = _train.info[k].full:cuda()
            _train.info[k].fullSparse = _train.info[k].fullSparse:cuda()
         end
     end

  end
  
  toGPU("U")
  toGPU("V")
  
end


--compute neural network
local network
if configU then

   -- unbias U
   for k, u in pairs(train.U.data) do
      u[{{}, 2}]:add(-train.U.info[k].mean) --center input
   end

   rmse, network = trainU(train, test, configU)
   
elseif configV then

   --unbias V
   for k, v in pairs(train.V.data) do
      train.V.info[k] = train.V.info[k] or {}     
      train.V.info[k].mean = v[{{}, 2}]:mean()
   
      v[{{}, 2}]:add(-train.V.info[k].mean) --center input
   end

   rmse, network = trainV(train, test, configV)
end

if #params.save > 0 then
   torch.save(params.save, network)
end


print("done!")



