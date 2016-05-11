local app = require('waffle') {
    autocache = false,
		public = './public'
}
local jpg = require 'libjpeg'
local math = require 'math'
local image = require 'image'
--local base64 = require "base64"
require 'nn'
require 'cutorch'
require 'cudnn'
local inn = require 'inn'
--local ltn12 = require("ltn12")
local http = require("socket.http")
local ffi = require "ffi"
ffi.cdef "unsigned int sleep(unsigned int seconds);"

function trim5(s)
  return s:match'^%s*(.*%S)' or ''
end

function load_labels()
  local file = io.open 'models/classid.txt'
  local list = {}
  while true do
    local line = file:read()
    if not line then break end
    table.insert(list, line) -- string.sub(line,11)
  end
  return list
end

function load_productMeta()
  local file = io.open("models/prdimgsurls.csv", 'r')
  local productURL = {}
  while true do
    local line = file:read()
    if not line then break end
    local pattern = "(.+),(.+),(.+),(.+),(.+),(.+)$"
    local key, imgurl, imgthmb, product_url, combo_type, on_site = line:match(pattern)
    productURL[key] = {imageURL = imgurl, imageThumbURL = imgthmb, url = product_url}
  end
  return productURL
end

local image_name = '/home/ubuntu/raw/BM239/443918.jpg'
local img_mean_name = 'models/ilsvrc_2012_mean.t7'

app.img_mean = torch.load(img_mean_name).img_mean:transpose(3,1)
--app.net = load_net()
app.net = torch.load("models/deepDress.t7")
app.styles = load_labels()
app.productMeta = load_productMeta()
app.datadir = 'data/'
print(app.net)

function getValue(tbl, key)
  for k,v in pairs(tbl) do
    if key == k then
      return v
    end
  end
  return "NA"
end

-- Converts an image from RGB to BGR format and subtracts mean
function preprocess(im, img_mean)
  -- rescale the image
  local im3 = image.scale(im,224,224,'bilinear')*255
  -- RGB2BGR
  local im4 = im3:clone()
  im4[{1,{},{}}] = im3[{3,{},{}}]
  im4[{3,{},{}}] = im3[{1,{},{}}]

  -- subtract imagenet mean
  return im4 - image.scale(img_mean, 224, 224, 'bilinear')
end

function predict(image_name, top_n, facet)
  --local im = image.load(image_name)
  print("Opening image " .. app.datadir .. image_name)
  local im = image.load(app.datadir .. image_name)
  print("Pre-processing")
  local I = preprocess(im, app.img_mean)
  -- Propagate through the network and sort outputs in decreasing order and show 5 best classes
  local prob,classes = app.net:forward(I:cuda()):view(-1):float():sort(true)
  local styleNames = {}
  for i = 1,math.min(top_n, classes:size(1)) do
    local style = {}
    local styleName = app.styles[classes[i]]
    local productMetaValue = getValue(app.productMeta, styleName)
      style = {
          style = styleName,
          probability = math.floor(10000 * prob[i])/100,
          urls = productMetaValue
      }
			if facet == "simple" then
      	styleNames[i] = styleName
			else 
      	styleNames[i] = style
			end
  end
  return styleNames
end 

function os.capture(cmd, raw)
  local f = assert(io.popen(cmd, 'r'))
  local s = assert(f:read('*a'))
  f:close()
  if raw then return s end
  s = string.gsub(s, '^%s+', '')
  s = string.gsub(s, '%s+$', '')
  s = string.gsub(s, '[\n\r]+', ' ')
  return s
end

function version()
	local version = {
		algorithm = "1.0-deep5",
		api = "1.0"
	}
	return version
end

app.get('/predict/', function(req, res)
   local t = {}
   local top_n = 6
   local file_id = "441498.jpg"
   local simple = "full"
--   if req.url.args.file_id ~= nil then 
   local file_id = req.url.args.file_id
--   end
   print("Predicting on " .. file_id)
   if req.url.args.top_n ~= nil then 
     top_n = tonumber(req.url.args.top_n) 
   end
   if req.url.args.facet ~= nil then 
     simple = req.url.args.facet
   end
   --t["styleNames"] = predict(req.url.args.file_id, top_n)
   t = predict(req.url.args.file_id, top_n, simple)
   res.json{styleNames = t, versions = version()}
end)

app.get('/', function(req, res)
   res.json{status="ok"}
end)


function getname(ext)
    return os.time() .. '-' .. math.floor(math.random() * 100000) .. ext
end

app.post('/image/', function(req, res)
   -- print(req)
   local img = base64.decode(req.body)
   --local tmpfile = os.tmpname()
   local tmpfile = getname('.jpeg')
   print("writing out " .. tmpfile)
   local tmphandle = assert(io.open(app.datadir .. tmpfile, 'wb'))
 
   tmphandle:write(img)
   io.close(tmphandle)
   res.json{file_id=tmpfile}
end)

-- this endoiint doesn't seem to work after upgrade
--app.get('/fetchimage/', function(req, res)
--   local img = base64.decode(req.body)
--   --local tmpfile = os.tmpname()
--   local tmpfile = getname(req.body)
--   local tmphandle = ltn12.sink.file(io.open(app.datadir .. tmpfile, 'w'))
--   http.request {
--     url = req.url.args.url,
--     sink = tmphandle
--   }
--   res.json{file_id=tmpfile}
--end)
--
app.get('/list/', function(req, res)
   res.json{files = os.capture('ls -rt ' .. app.datadir, true)}
end)

app.get('/chrome/', function(req, res)
	res.header('Content-Type', 'application/x-chrome-extension')
		.sendFile('./public/RTR.crx')
end)

app.get('/wget/', function(req, res)
		local ext = string.gsub(req.url.args.url, '.*%.', '')
    local tmpfile = getname('.' .. ext)
    local wget = os.capture("wget -U 'Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:14.0) Gecko/20100101 Firefox/14.0.1' -O " .. app.datadir .. tmpfile .. "  " .. req.url.args.url) 
    print("got file " .. tmpfile)
    res.json{file_id = tmpfile}
end)

app.post('/imageraw/', function(req, res)
    -- local tmpfile = req.form.file.filename
    local tmpfile = getname('.jpeg')

    print("got file " .. tmpfile ..'!')
    req.form.file:save{path = app.datadir .. tmpfile}
    res.json{file_id = tmpfile}
end)

--- DONOTUSE -- couldn't get this to work.. maybe an async issue but not sure
app.post('/imagepredict/', function(req, res)
    -- local tmpfile = req.form.file.filename
    local tmpfile = getname('.jpeg')

    print("got file " .. tmpfile ..'!')
    req.form.file:save{path = app.datadir .. tmpfile}
    ffi.C.sleep(10)
    local top_n = 5
    local t = predict(tmpfile, top_n)
    res.json{styleNames = t}
end)


app.get('/upload/', function(req, res)
   res.send(html { body { form {
      action = '/imageraw/',
      --action = '/imagepredict/',
      method = 'POST',
      enctype = 'multipart/form-data',
      p { input {
         type = 'text',
         name = 'top_n',
         placeholder = 'Number of close matches requested'
      }},
     p { input {
         type = 'file',
         name = 'file'
      }},
      p { input {
         type = 'submit',
         'Upload'
      }}
   }}})
end)

-- couldn't get template to work either.. using brute force to save time
-- TODO: This is a hack
app.get('/demo/', function(req, res)
   res.header('Content-Type', 'text/html')
   res.send[[

<!DOCTYPE html>
<html>
<head>
<title>Deep Dress</title>
<link rel="icon" type="image/png" href="./public/icon_16.png">
<script src="https://ajax.googleapis.com/ajax/libs/jquery/1.11.3/jquery.min.js"></script>
<script src="http://malsup.github.com/jquery.form.js"></script> 
<meta name="viewport" content="width=device-width, initial-scale=1.0 maximum-scale=1, user-scalable=no"">
<meta name="description" content="Find your dream dress harnessing advances in deep learning" />

<!-- Latest compiled and minified CSS -->
<link rel="stylesheet" href="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.5/css/bootstrap.min.css">

<!-- Optional theme -->
<link rel="stylesheet" href="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.5/css/bootstrap-theme.min.css">

<style>
body {
  padding-top: 50px;
}
.starter-template {
  padding: 40px 15px;
  text-align: center;
}
.caption {
  text-align: center;
}
</style>

<script>
  (function(i,s,o,g,r,a,m){i['GoogleAnalyticsObject']=r;i[r]=i[r]||function(){
  (i[r].q=i[r].q||[]).push(arguments)},i[r].l=1*new Date();a=s.createElement(o),
  m=s.getElementsByTagName(o)[0];a.async=1;a.src=g;m.parentNode.insertBefore(a,m)
  })(window,document,'script','//www.google-analytics.com/analytics.js','ga');

  ga('create', 'UA-72105927-1', 'auto');
  ga('send', 'pageview');

</script>


<!-- Latest compiled and minified JavaScript -->
<script src="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.5/js/bootstrap.min.js"></script>

<script>

$(document).ready(function() { 
    var options = {
        success:   showResponse,
        dataType:  'json'
    };
    // bind 'myForm' and provide a simple callback function 
    $('#myForm').ajaxForm(options); 
    function showResponse(responseText, statusText, xhr, $form)  { 
        var file_id = xhr.responseJSON.file_id;
        console.log("file_id: ",  file_id);
        $.ajax({ url: "/predict/?file_id=" + file_id, dataType: "json", success : function(result) {
            //$("div").html(JSON.stringify(result));
            $('#results').empty();
            $('#result-header').show('slow');
            //for(i=0; i<5; i++) { $('#slider_list').append("<li class = 'list-group-item'><img src='" + result.styleNames[i]["images"]["imageThumbURL"] + "' class='img-thumbnail'/></li>");};
            //for(i=0; i<5; i++) { $('#results').append("<div class='col-md-4'><img src='" + result.styleNames[i]["images"]["imageThumbURL"] + "' class='img-thumbnail'/></div>");};
            //for(i=0; i<5; i++) { $('#results').append("<div class='col-md-4'><p><img src='" + result.styleNames[i]["images"]["imageThumbURL"] + "' class='img-thumbnail'/></div><div class='caption'>" + result.styleNames[i]["style"] + " with " + result.styleNames[i]['probability'] + "% chance </p></div>");};
            for(i=0; i<5; i++) { $('#results').append("<div class='col-sm-6 col-md-4'><div class='thumbnail'><a href='" + result.styleNames[i]["urls"]["url"] + "?utm_medium=deepdress' target='_blank'><img src='" + result.styleNames[i]["urls"]["imageURL"] + "' class='img-responsive'/></a><div class='caption'><h5>" + result.styleNames[i]['probability'] + "% match </h5> </div></div>");};
        }});
    };
}); 

</script>
</head>

<body role="document">
    <nav class="navbar navbar-inverse navbar-fixed-top">
      <div class="container">
        <div class="navbar-header">
          <button type="button" class="navbar-toggle collapsed" data-toggle="collapse" data-target="#navbar" aria-expanded="false" aria-controls="navbar">
            <span class="sr-only">Toggle navigation</span>
            <span class="icon-bar"></span>
            <span class="icon-bar"></span>
            <span class="icon-bar"></span>
          </button>
          <a class="navbar-brand" href="#">Deep Dress</a>
        </div>
        <div id="navbar" class="navbar-collapse collapse">
          <ul class="nav navbar-nav">
            <li><a href="#match">Dress Match</a></li>
            <li><a href="#about">About</a></li>
            <li><a href="#faq">FAQ</a></li>
            <li><a href="#api">API</a></li>
          </ul>
        </div><!--/.nav-collapse -->
      </div>
    </nav>
    
    <div class="container theme-showcase" role="main">

        
        <div class="page-header">
            <h2 id="match"><span class="glyphicon glyphicon-camera" aria-hidden="true"></span></h2>
        </div>

				<div class = "jumbotron">
        <form id="myForm" action="/imageraw/" method="post" class="form-inline" role="form">
						<big>
            <div class="form-group" style="margin-right:10px">
                <h2>
                <label for="file"></label>
                </h2>
                <input type="file" name="file"  accept="image/*"></input> 
            </div>
						</big>
						<hr>
            <button type="submit" class="btn btn-default">Find me a dress</button>
        </form>
        </div>

        <h5 id="result-header" style="display: none">Ready to rent</h5>
        <div>
            <div class="row">
                <label id="results"> </label>
            </div>
        </div>
        

        <div class="page-header">
            <h3 id="about">About</h3>
        </div>

        <p>
        No more dress envy! Shazam for dresses is here. Submit a photo and Deep Dress AI will use deep learning techniques to visually look at dresses find you something to rent.
        </p>

        <div class="page-header">
            <h3 id="faq">FAQ</h3>
        </div>

        <p class="lead">
        <h4>I cannot take a photo </h4>
        This works for some newer iPhones and Android. Your version might not support it. Please choose a photo the old way or use on desktop. Also, this currently works for JPEGs only.
        <h4>I can't find the dress</h4>
        Currently AI doesn't know about all RTR products.

        <h4>The results are wonky</h4>
        Sorry to hear that. Can you send me the photo you used and a screenshot of what you got back.

        <h4>What is deep learning?</h4>
        We can create end-to-end models that learn the important features from these dress photos and the model at the same time. I am using convolution nets.

        <h4> What can RTR do with this? </h4>
        There are many ideas in-flight for just being able to auto-tag images, product similarity and mobile applications. Besides those, I am actively doing research to improve this model and use these representations to drive other products like recommendations and fit.

        <h4>What tools did you use?</h4>
        I trained models using caffe and torch. This website and API are hosted via waffle and is written in lua. I used python for data processing.

        <h4> This is cool. Can I create an application for this?</h4>
        Glad you asked. API and code are coming soon. I will write up the methodology on <a href="http://www.sanealytics.com/" target="_blank">my blog</a>.

        </p>

        <div class="page-header">
            <a name="api"></a>
            <h3>API and code</h3>
        </div>

        <div class="panel panel-default">
        <div class="panel-heading"><bold>POST</bold> to /imageraw/ Use multipart form and put JPEG in variable named file</div>
        <div class="panel-body">
        <pre id="json">
{
  "file_id": "123456.jpeg"
}
</pre>
        </div>
        </div>

        <div class="panel panel-default">
        <div class="panel-heading"><bold>GET</bold> to /wget/?url=http://myurl/image.jpeg to tell DeepDress to fetch the image</div>
        <div class="panel-body">
        <pre id="json">
{
  "file_id": "123456.jpeg"
}
</pre>
        </div>
        </div>
 
        <div class="panel panel-default">
        <div class="panel-heading"><bold>GET</bold> /predict/?file_id=123456.jpeg&top_n=2&facet=full [top_n and facet=simple are optional]</div>
        <div class="panel-body">
        <pre id="json">
{
  "styleNames": [
    {
      "style": "NK7",
      "urls": {
        "imageURL": "https:\/\/pc-ap.renttherunway.com\/productimages\/side\/270x\/23\/NK7.jpg",
        "imageThumbURL": "https:\/\/pc-ap.renttherunway.com\/productimages\/side\/70x\/23\/NK7.jpg",
        "url": "http:\/\/www.renttherunway.com\/shop\/designers\/nha_khanh\/north_dress"
      },
      "probability": 32.52
    },
    {
      "style": "TT71",
      "urls": {
        "imageURL": "https:\/\/pc-ap.renttherunway.com\/productimages\/front\/270x\/be\/TT71.jpg",
        "imageThumbURL": "https:\/\/pc-ap.renttherunway.com\/productimages\/front\/70x\/be\/TT71.jpg",
        "url": "http:\/\/www.renttherunway.com\/shop\/designers\/trina_turk\/paper_cut_jumpsuit"
      },
      "probability": 12.55
    }
  ]
}
</pre>
        </div>
        </div>

        <p>
        Code to be released soon
        </p>

        <hr>
        <footer>
            Made by <a href="mailto:saurabh.writes+deepdress@gmail.com">Saurabh Bhatnagar</a>, Data Scientist at <a href="http://www.renttherunway.com" target="_blank">Rent The Runway</a>
        </footer>

    </div>

</body>
</html>

   ]]
end)


app.listen({host = '0.0.0.0', port = 8080})

