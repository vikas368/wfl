// Generated by CoffeeScript 1.3.3
(function() {
  var inspect, models;

  inspect = (require('eyes')).inspector();

  models = require("../lib/models");

  exports.run = function(options) {
    var activitiOpt, activity;
    activitiOpt = {
      'accessKeyId': options.accessKeyId,
      'secretAccessKey': options.secretAccessKey,
      'region': options.region,
      'domain': options.domain,
      'taskList': {
        'name': options.taskList
      }
    };
    return activity = new models.Activity(activitiOpt, function(err, task) {
      var activityResult;
      if (err != null) {
        console.log("Error while executing: new Activity");
      }
      inspect(task, "Got task:");
      activityResult = {
        "value": "Hello, "
      };
      return task.respondCompleted(activityResult, function(error, result) {
        if (error != null) {
          return inspect(error, "error");
        }
      });
    });
  };

}).call(this);
