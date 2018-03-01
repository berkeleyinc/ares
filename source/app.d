import std.stdio;
import std.conv;
import std.typecons;
import std.algorithm;
import std.process;

import vibe.vibe;
import vibe.web.web;
import vibe.http.fileserver;
import vibe.http.router;
import vibe.http.server;
import vibe.stream.wrapper;
import diet.html;

import web.service;

import config;

void main(string[] args) {
  ushort port = cast(ushort) Cfg.get[Cfg.G.SRV_port].as!ushort;
  string listenIP = Cfg.get[Cfg.G.SRV_listenIP].str;


  auto router = new URLRouter;



  // router.get("/", &processRequest);
  // router.get("/graph/*", &processGetGraph);
  // router.get("/res/*", &processRestructure);
  // router.get("/set/dot/*", &processSetDotOption);
  router.registerWebInterface(new WebService);
  router.get("*", serveStaticFiles("public/"));
  // registerRestInterface!IRestAPI(router, new Rest(), "/rest");

  auto settings = new HTTPServerSettings;
  settings.port = port;
  settings.sessionStore = new MemorySessionStore;

  immutable string localIP = "127.0.0.1";
  settings.bindAddresses = [localIP];
  if (listenIP.length > 0)
    settings.bindAddresses ~= listenIP;

  listenHTTP(settings, router);
  runApplication();
  return;
}


