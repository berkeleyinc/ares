function draw(data) {
  var svg_div = $('#graph');
  svg_div.hide();
  var svg = Viz(data, "svg");
  svg_div.html(svg);
  svg = svg_div.children(0);
  // var svg = $('#graph > svg');

  svg.css("width", "100%");
  svg.css("margin-top", "30pt");
  svg.css("height", "100%");
  svg.children(0).children('g.node').each(function () {
    var node = $(this);
    var name = node.children('title')[0].innerHTML;
    this.style.cursor = 'pointer';
    this.setAttribute("data-toggle", "popover");
    this.setAttribute("data-selector", "node-popover");
    this.setAttribute("data-container", "body");
    this.setAttribute("data-title", "Node " + name);
    this.setAttribute("data-html", true);
    this.setAttribute("data-trigger", "manual");

    this.onmouseenter = function() {
      nodePopover(node, name);
    };

  });
  $('.node-popover').popover();
  svg_div.html(svg).show(); //.fadeIn();
  $(window).scrollTop($('#vizTabsNav').position().top);
  // console.log("svg drawn");
}

function createPopoverButtonGroupContent(fid, vn, soup, check, cont) {
  soup.forEach(function(oid) {
    var objCheckDiv = $('#objCheckDiv').clone().removeAttr("style");
    var label = objCheckDiv.children('label');
    label[0].childNodes[0].nodeValue = 'F' + oid;
    if (check)
      check.forEach(function(depId) {
        if (oid == depId) {
          label.addClass('active');
        }
      });
    label[0].setAttribute('fid', fid);
    label[0].setAttribute(vn, oid);
    cont.html(cont.html() + objCheckDiv.html());
  });
}

function addPopoverButtonGroupClickHandlers(node, name) {
  var cls = ["depends-on", "quals", "assigned"],
    vns = ["did", "qid", "did"];
  for (var i = 0; i < cls.length; i++) (function() {
    var groupName = cls[i], varName = vns[i], idx = i;
    $('.popover').find('div.' + groupName + '-group > label').click(function() {
      var fid = this.getAttribute('fid'),
        iid = this.getAttribute(varName);
      console.log('fid=' + fid + ", " + varName + "=" + iid);
      $.get('/set_object_config?id=' + fid +'&' + varName + '=' + iid, null, function (data) {
        if (data != 'OK')
          console.error("Failed to set " + groupName + " value on: " + 'fid=' + fid + ", iid=" + iid);
        else {
          switch (idx) {
            case 1: 
              node.popover('dispose');
              nodePopover(node, name);
              break;
            case 2: 
              requestDotData();
              break;
            default:
              break;
          }
        }
      });
    });
  }());
}
function onBranchProbInputChange() {
  var newProb = $(this).val(),
    cid = this.getAttribute('cid'),
    oid = this.getAttribute('oid');
  console.log("newProb=" + newProb + ", cid=" + cid + ", oid=" + oid);
  $.get('/set_object_config?id=' + cid +'&oid=' + oid + '&p=' + newProb, null, function (data) {
    if (data != 'OK')
      console.error("Failed to set branch prob on: " + 'cid=' + cid);
  });
}

function nodePopover(node, name) {
  console.log(name);
  $('[data-toggle="popover"]').popover('dispose');
  var nodeDiv = $('#nodeDiv').clone().prop('id', 'nodeDiv-' + name).css("display", "block");
  var fid = name.substring(1);

  $.get('/object_config?id=' + fid, null, function (res) {
    var table = nodeDiv.children('table');
    var node_dur = table.find('tr.node-dur');
    // var node_opt = table.find('tr.node-opt');
    var node_funcs = table.find('tr.node-funcs');
    var node_quals = table.find('tr.node-quals');
    var node_assigned = table.find('tr.node-assigned');
    var node_probs = table.find('tr.node-probs');
    table.find('tr.node-class').children('td').html(res.class);
    if (res.class == 'Function') {
      node_quals.remove();
      node_assigned.remove();
      node_probs.remove();
      var inp_dur = node_dur.find('td > input');
      inp_dur[0].setAttribute('fid', fid);
      inp_dur[0].setAttribute('value', res.dur);;
      // node_opt.children('td').text(res.opt);
      var c = node_funcs.children('td').children('div');
      createPopoverButtonGroupContent(fid, 'did', res.beforeFuncs, res.dependsOn, c);
    } else {
      node_dur.remove();
      // node_opt.remove();
      node_funcs.remove();
      if (res.class == 'Participant') {
        node_probs.remove();
        var cq = node_quals.children('td').children('div'), ca = node_assigned.children('td').children('div');
        createPopoverButtonGroupContent(fid, 'qid', res.allFuncs, res.quals, cq);
        createPopoverButtonGroupContent(fid, 'did', res.quals, res.deps, ca);
      } else {
        node_quals.remove();
        node_assigned.remove();
        if (res.class == 'Connector') {
          var c = node_probs.children('td').children('div');
          if (res.probs)
            for (var i = 0; i < res.probs.length; i++) {
              if (i > 0)
                c = c.after(c[0].outerHTML);
              c.children('label')[0].childNodes[0].nodeValue = 'N' + res.probs[i][0];
              var inp = c.children('input');
              inp[0].setAttribute('cid', fid); // Connector ID
              inp[0].setAttribute('oid', res.probs[i][0]); // ID of connected branch obj
              inp[0].setAttribute('value', res.probs[i][1]);
            }
          else
            node_probs.remove();
        } else {
          node_probs.remove();
        }
      }
    }
    node.attr("data-content", nodeDiv[0].outerHTML);

    node.popover('show');
    var fn_hide = function() { 
      $('.popover.show').remove();
      /*node.popover('hide');*/
    };
    $('.popover.show').mouseleave(fn_hide);
    $('.popover.show > .popover-header').mouseleave(fn_hide);
    $('tr.node-probs > td > div > input').change(onBranchProbInputChange);
    $('tr.node-dur > td > input').change(function() {
      $.get('/set_object_config?id=' + $(this).attr('fid') +'&dur=' + $(this).val(), null, function (data) {
        if (data != 'OK')
          console.error("Failed to set func duration");
      });
    });
    addPopoverButtonGroupClickHandlers(node, name);

  });
}

function setLog(data) {
  var log = $('#log') 
  log.text(data);
  log[0].scrollTop = log[0].scrollHeight;
  log.css("opacity", "1.0");
}

function addVizTab(tabTitle = '', navigateToNewTab = true) {
  var id = $("#vizTabsNav").children().length; 
  var tabId = 'vizTab-' + id;
  var lastNav = $('#vizTabsNav li:last-child');
  var newNavLi = lastNav.clone();
  var newNav = newNavLi.children().prop('href', '#' + tabId).removeClass('active');
  newNav[0].childNodes[0].nodeValue = (tabTitle.length > 0 ? tabTitle : "BP " + (id + 1));
  // console.log(newNavLi[0].outerHTML);
  lastNav.after(newNavLi[0].outerHTML);
  var lastCont = $('#vizTabsContent div:last-child');
  var tabCont = lastCont.clone().prop('id', tabId).removeClass('active');
  // console.log(tabCont[0].outerHTML);
  lastCont.after(tabCont[0].outerHTML);

  if (navigateToNewTab) {
    $('#vizTabsNav li:nth-child(' + (id + 1) + ') a').click();
  }
  updateVizTabClickHandlers();
}

function requestDotData(id = -1) {
  $('.popover.show').remove();
  $.get('/graph?id=' + id, null, function (data) {
    draw(data); 
  });
}

function requestGeneration() {
  $('#vizTabsNav li:first-child a').click();
  var firstNav = $('#vizTabsNav li:first-child').clone();
  $('#vizTabsNav').children().remove();
  // console.log(firstNav[0].outerHTML);
  $('#vizTabsNav').append(firstNav[0].outerHTML);

  var firstCont = $('#vizTabsContent div:first-child');
  $('#vizTabsContent').children().remove();
  $('#vizTabsContent').append(firstCont[0].outerHTML);

  $.get('/gen', null, function (data) {
    // addVizTab();
    // setLog(''); //data.log);
    setLog(data.log);
    draw(data.dot);
  });
}

function requestRestructuring() {
  setLog("Processing ...");
  $('#log').css("opacity", "0.3");
  $.get('/res', null, function (data) {
    setLog(data.log);
    for (var i = 0; i < data.dots_len; i++) {
      addVizTab('', false);
      // draw(data.dot);
    }
  });
}

function requestSimulation() {
  setLog("Simulations in progress ...");
  $('#log').css("opacity", "0.3");
  $.get('/sim/start', null, function (data) {
    setLog(data);
  });
}

function requestClone() {
  $.get('/clone', null, function (data) {
    addVizTab();
    draw(data);
  });
}

function requestSetOption(category, what) {
  $.get('/set/' + category + '?' + what, null, function (data) {
    // draw(data); 
    requestDotData(); 
  });
}

function onSiteReady() {
  jQuery.ajaxSetup({
    error: function(resp, e) {
      console.log(resp.responseText);
      if (resp.status == 0){
        alert('Server not reachable.');
      } else if (resp.status == 404){
        alert('Requested URL not found.');
      } else if (resp.status == 500){
        alert(resp.responseText);
      } else if (e == 'parsererror') {
        alert('Error.\nParsing JSON Request failed.');
      } else if (e == 'timeout') {
        alert('Request timeout.');
      } else {
        alert('Unknown Error.\n' + resp.responseText);
      }
    }
  });

  // --- main tab ---
  $("#btnGen").click(function () { requestGeneration(); });
  $("#btnSim").click(function () { requestSimulation(); });
  $("#btnRes").click(function () { requestRestructuring(); });
  $("#btnClone").click(function () { requestClone(); });
  $("#btnClearLog").click(function () { setLog(''); });

  // --- options tab ---
  $("#btnShowParts").click(function () { requestSetOption('dot', 'opts_showParts=true'); });
  $("#fileInput").change(function() {
    $.ajax({
      url: '/upload',
      type: 'POST',

      data: new FormData($('#uploadAresForm')[0]),

      // Tell jQuery not to process data or worry about content-type
      cache: false,
      contentType: false,
      processData: false,

      success: function (res) {
        console.log("Upload of ares.bin successful");
        draw(res);
      }
    });
  });

  // $('#cfgDiv > div > div > input').prop('disabled', true);
  // $('#cfgDiv > div > div > input').change(function() {
  //   console.log("change " + this.id + " to " + $(this).val());
  //   // $.get('/set_config', null, function (data) {
  //   // });
  //   // $(this).val()
  // });
  $.get('/config', null, function (data) {
    var cfg = JSON.parse(data);
    var cfgProps = Array.from({length: 5}, i => 'value').concat(['checked']);
    var cfgInpIDs = ['BD', 'FC', 'SPP', 'RPS', 'TBR', 'RCP'];
    var cfgEntries = ['GEN_maxDepth', 'GEN_maxFuncs', 'SIM_simsPerBP', 'SIM_parRunnersPerSim', 'SIM_timeBetweenRunnerStarts', 'SIM_reuseChosenPaths'];
    var setConfig = function(key, val) {
      console.log("set_config, key="+key+", val="+val);
      $.get('/set_config?key=' + key + "&val=" + val);
    }
    for (var i = 0; i < cfgInpIDs.length; i++) {
      $('#inp' + cfgInpIDs[i]).prop(cfgProps[i], cfg[cfgEntries[i]]);
      $('#inp' + cfgInpIDs[i]).change(function (i){return function() { setConfig(cfgEntries[i], this[cfgProps[i]]); }}(i));
    }
    for (var i = 0; i < cfg.GEN_branchTypeProbs.length; i++) {
      $('#inpP' + i).val(cfg.GEN_branchTypeProbs[i]);
      $('#inpP' + i).change(function (i){return function() { setConfig("GEN_branchTypeProbs/" + i, $(this).val()); }}(i));
    }
    for (var i = 0; i < cfg.GEN_branchCountProbs.length; i++) {
      $('#inpBC' + i).val(cfg.GEN_branchCountProbs[i]);
      $('#inpBC' + i).change(function (i){return function() { setConfig("GEN_branchCountProbs/" + i, $(this).val()); }}(i));
    }
    for (var i = 0; i < cfg.GEN_avgFuncDurs.length; i++) {
      $('#inpFD' + i).val(cfg.GEN_avgFuncDurs[i]);
      $('#inpFD' + i).change(function (i){return function() { setConfig("GEN_avgFuncDurs/" + i, $(this).val()); }}(i));
    }
    // console.log(cfg);
  });


  // --- generate graph ---
  requestDotData();
  updateVizTabClickHandlers();

  // delete Popover when mouse moving over body
  $('body').mouseenter(function() {
    $('.popover.show').remove();
  });
}

function updateVizTabClickHandlers() {
  // $('#graph');
  $('#vizTabsNav > li > a[data-toggle="tab"]').on('shown.bs.tab', function (e) {
    var bpId = e.target.getAttribute('href').split('-')[1];
    console.log("REQUEST BP_ID " + bpId); // newly activated tab
    requestDotData(bpId);
    // console.log(e.relatedTarget) // previous active tab
  });
}

function deobfuscate(s) {
  var n = 0;
  var r = "";
  for(var i = 0; i < s.length; i++) {
    n = s.charCodeAt( i );
    if ( n >= 8364 )
      n = 128;
    r += String.fromCharCode( n - 1 );
  }
  return r;
}

function linkto_deobfuscate(s) {
  location.href = deobfuscate(s);
}

$(document).ready(onSiteReady);
