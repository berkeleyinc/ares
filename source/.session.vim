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
badd +39 proc/mod/businessProcessModifier.d
badd +123 proc/sim/simulator.d
badd +79 proc/mod/assignMod.d
badd +94 proc/mod/moveMod.d
badd +169 proc/sim/pathFinder.d
badd +1 proc/businessProcess.d
badd +98 proc/businessProcessGenerator.d
badd +317 web/service.d
badd +213 ~/th/code/ares/public/js/site.js
badd +1 proc/epcElement.d
badd +52 graphviz/dotGenerator.d
badd +1 proc/event.d
badd +1 proc/func.d
badd +41 proc/gate.d
badd +55 proc/sim/multiple.d
badd +12 proc/businessProcessExamples.d
badd +32 config.d
badd +87 proc/mod/parallelizeMod.d
badd +50 proc/sim/token.d
badd +1 proc/mod/modification.d
badd +1 app.d
badd +4 proc/agent.d
badd +13 proc/sim/simulation.d
badd +38 web/sessions.d
badd +4 ~/th/code/ares/dub.json
argglobal
silent! argdel *
edit web/service.d
set splitbelow splitright
wincmd t
set winminheight=0
set winheight=1
set winminwidth=0
set winwidth=1
argglobal
setlocal fdm=manual
setlocal fde=0
setlocal fmr={{{,}}}
setlocal fdi=#
setlocal fdl=0
setlocal fml=1
setlocal fdn=20
setlocal fen
silent! normal! zE
let s:l = 285 - ((20 * winheight(0) + 21) / 42)
if s:l < 1 | let s:l = 1 | endif
exe s:l
normal! zt
285
normal! 05|
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
