local utils = require 'mp.utils'

function get_extension(path)
    retval = string.match(path,"%.([^%.]+)$")
    return retval
end

--获取文件名，不包含扩展名
--例如filename.cmt.xml得到的结果为filename
function get_filename(path)
    retval = string.match(path,"/?(%.?[^/%.]+)[^/]+$")
    return retval
end

--mpv给的接口会把命令行需要的转义符\干掉，这个函数是为了把转义符加回来
function render_path(path)
    retval = string.gsub(path,
        "([%s%~%!%#%$%%%&%*%(%)%`%=%{%}%|%[%]%\\%;%'%\"%<%>%?%,%:])","\\%1")
    return retval
end

--filter the table, kill all the elements that don't satisfy the condition iter
table.filter = function(t,iter)
    for i = #t,1,-1 do
        if not iter(t[i]) then
            table.remove(t,i)
        end
    end
end

table.run = function(t,func)
    for k,v in pairs(t) do
        func(k,v)
    end
end

--Attach all the string in table t, seperated by sep, which is a space by default
function table2string(t,sep)
    if sep == nil then sep = ' ' end
    local retval = ""
    if #t < 1 then return retval end
    retval = retval..tostring(t[1])
    for i = 2,#t,1 do
        retval = retval..sep..tostring(t[i])
    end
    return retval
end

---[[
mputils = require 'mp.utils'
cjson = require 'cjson'
PERFIX = '/tmp/loadxml_mpv/'

tmpfiles = {
    json = PERFIX..'stream_info.json'
}

function init()
    local init_cmd_table = {
        "if [ ! -e ",PERFIX," ];",
        "then mkdir ",PERFIX,";",
        "fi"
    }
    os.execute(table2string(init_cmd_table,""))
end

--remove all tmp files
function cleanup()
    table.run(tmpfiles,print)
    local rm_cmd = {'rm'}
    for key,file in pairs(tmpfiles) do
        table.insert(rm_cmd,file)
        if key ~= 'json' then tmpfiles[key] = nil end
    end
    os.execute(table2string(rm_cmd))
end

--return video size width,height
function getsize()
    local path,err = mp.get_property("path","")
    if path == "" then
        print(err)
        return 0,0
    end
    local ffprobe_cmd_table = {
        "ffprobe",
        "-loglevel","repeat+warning",
        "-print_format","json",
        "-select_streams","v",
        "-show_streams",render_path(path),
        ">"..tmpfiles.json
    }
    os.execute(table2string(ffprobe_cmd_table))
    local dataJson = io.open(tmpfiles.json,'r')
    local data = dataJson:read('*a')
    data = cjson.decode(data)
    dataJson:close()

    if data == nil then
        return 0,0
    end
    if data.streams == nil then
        return 0,0
    end
    if data.streams[1] == nil then
        return 0,0
    end
    if data.streams[1].width == nil or data.streams[1].height == nil then
        return 0,0
    end

    local w,h = data.streams[1].width,data.streams[1].height
    return tonumber(w),tonumber(h)
end

--search file directory and find danmaku file
--the danmaku file need to have same file name with the video
function find_xml()
    local path = mp.get_property("path","")
    local dir,filename = mputils.split_path(path)
    if #dir == 0 then
        return {}
    end
    filename = get_filename(path)
    local files = mputils.readdir(dir,"files")
    if files == nil then
        return {}
    end
    table.filter(files, function (f)
        local ext = get_extension(f)
        if ext == nil then
            return false
        end
        return string.lower(ext) == 'xml'
    end)
    table.filter(files,function(f)
        local name = get_filename(f)
        if name == nil then
            return false
        end
        return name == filename
    end)
    return files
end

--convert danmaku to ass and load it
--need danmaku2ass installed
--You can obtain the latest copy of Danmaku2ASS at:
--    https://github.com/m13253/danmaku2ass
function danmaku2ass_load(dir,filename,width,height)
    local output_path = PERFIX.."tmp_danmaku2ass_"..get_filename(filename)..".ass"
    tmpfiles[#tmpfiles+1] = render_path(output_path)
    local danmaku2ass_cmd = {
        'danmaku2ass',
        '-s',tostring(width)..'x'..tostring(height),
        '-a',0.9,
        '-dm',15.0,--math.min(math.max(6.75*width/height-4, 3.0), 5.0),
        '-ds',5.0,
        '-fs',math.ceil(height/25),
        '-o',render_path(output_path),
        render_path(utils.join_path(dir, filename))
    }
    os.execute(table2string(danmaku2ass_cmd))

    local loadass_cmd = {
        'sub-add',
        '"'..output_path..'"',
        'select',
        'Danmaku'
    }
    mp.command(table2string(loadass_cmd))
end

function loadxml()
    init()
    local path = mp.get_property("path","")
    local dir,filename = mputils.split_path(path)
    local w,h = getsize()
    print(w,h)
    if w == 0 or h == 0 then return end
    local subs = find_xml()
    if #subs == 0 then return end
    danmaku2ass_load(dir,subs[1],w,h)
end

mp.register_event("start-file",loadxml)
mp.register_event("end-file",cleanup)
--]]
