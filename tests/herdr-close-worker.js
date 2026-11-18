import { mock } from "bun:test";
import assert from "node:assert/strict";
const calls=[],notifications=[];
mock.module("gpui-kit",()=>({View:class {},div(){},svg(){},image(){}}));
mock.module("gpui-base",()=>({h_flex(){}}));
mock.module("herdr",()=>({
 spaces:()=>[{id:"s",active:true,tabs:[{id:"mini/tab",active:true}]}],panes(){},run(){},theme(){},openOverlay(){},nextCommand(){},window(){},
 props:()=>({nativeHelper:"/installed/herdr-native"}),home:()=>"/home/fixture",
 shared(){},setShared(){},notify:n=>notifications.push(n),
 hc:async args=>{
  calls.push(args);
  if(args[0]==="run"){
   if(args[args.indexOf("--")+1]!=="/installed/herdr-native") return {code:1,stderr:'{"error":{"kind":"spawn_failed","message":"cannot find herdr-native"}}'};
   return {code:0,stdout:JSON.stringify({address:"worker"})};
  }
  return {code:0,stdout:JSON.stringify(args[0]==="get" ? {state:"finished",exit_code:0} : {})};
 }
}));
const {default:Bar}=await import("../dotfiles/herdr-app/compact-terminals-bar/main.js");
const view=new Bar();view.spaceId="s";view.selected=[];
let pending;
const cx={spawn:fn=>{pending=fn(cx)},notify(){}};
view.closeSelected(cx);await pending;
assert.deepEqual(notifications,[],"Close must launch in a core with a bare PATH");
assert.equal(calls[0][calls[0].indexOf("--")+1],"/installed/herdr-native");
assert.equal(calls[0][calls[0].indexOf("--cwd")+1],"/home/fixture");
assert.deepEqual(calls[0].slice(-3),["close-group","--tabs","mini/tab"]);
assert.equal(view.busy,false);
console.log("Close worker uses installed executable and explicit home directory");
