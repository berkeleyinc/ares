let SessionLoad = 1
if &cp | set nocp | endif
let s:so_save = &so | let s:siso_save = &siso | set so=0 siso=0
let v:this_session=expand("<sfile>:p")
silent only
silent tabonly
cd ~/th/code/ares/source
if expand('%') == '' && !&modified && line('$') <= 1 && getline(1) == ''
  let s:wipebuf = bufnr('%')
endif
set shortmess=aoO
badd +36 proc/mod/businessProcessModifier.d
badd +173 proc/sim/simulator.d
badd +80 proc/mod/assignMod.d
badd +92 proc/mod/moveMod.d
badd +152 proc/sim/pathFinder.d
badd +237 proc/businessProcess.d
badd +130 proc/businessProcessGenerator.d
badd +303 web/service.d
badd +314 ~/th/code/ares/public/js/site.js
badd +1 proc/epcElement.d
badd +1 graphviz/dotGenerator.d
badd +1 proc/event.d
badd +1 proc/func.d
badd +41 proc/gate.d
badd +64 proc/sim/multiple.d
badd +12 proc/businessProcessExamples.d
badd +163 config.d
badd +17 proc/mod/parallelizeMod.d
badd +278 proc/sim/token.d
badd +18 proc/mod/modification.d
badd +1 app.d
badd +4 proc/agent.d
badd +7 proc/sim/simulation.d
argglobal
silent! argdel *
set splitbelow splitright
wincmd t
set winminheight=0
set winheight=1
set winminwidth=0
set winwidth=1
argglobal
enew
file NERD_tree_1
setlocal fdm=manual
setlocal fde=0
setlocal fmr={{{,}}}
setlocal fdi=#
setlocal fdl=0
setlocal fml=1
setlocal fdn=20
setlocal nofen
lcd ~/th/code/ares/source
tabnext 1
if exists('s:wipebuf') && len(win_findbuf(s:wipebuf)) == 0
  silent exe 'bwipe ' . s:wipebuf
endif
unlet! s:wipebuf
set winheight=1 winwidth=20 shortmess=filnxtToOc
set winminheight=1 winminwidth=1
let s:sx = expand("<sfile>:p:r")."x.vim"
if file_readable(s:sx)
  exe "source " . fnameescape(s:sx)
endif
let &so = s:so_save | let &siso = s:siso_save
doautoall SessionLoadPost
unlet SessionLoad
" vim: set ft=vim :
