// Generated by CoffeeScript 1.3.3
(function() {
  var app, options, wfl, workflowOptions;

  wfl = require('../lib/wfl');

  options = {
    domain: "wfl-dev-2"
  };

  app = wfl(options);

  workflowOptions = {
    my_id: "" + Math.random(),
    name: "toto",
    filePath: "/dev/null"
  };

  app.start(workflowOptions);

}).call(this);