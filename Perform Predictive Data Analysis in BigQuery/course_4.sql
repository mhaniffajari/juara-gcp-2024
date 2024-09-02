--predict penalty percentage
SELECT
 playerId,
 (Players.firstName || ' ' || Players.lastName) AS playerName,
 COUNT(id) AS numPKAtt,
 SUM(IF(101 IN UNNEST(tags.id), 1, 0)) AS numPKGoals,

 SAFE_DIVIDE(
   SUM(IF(101 IN UNNEST(tags.id), 1, 0)),
   COUNT(id)
   ) AS PKSuccessRate

FROM
qwiklabs-gcp-02-eae74eb47bb6.soccer.events183 Events

LEFT JOIN
qwiklabs-gcp-02-eae74eb47bb6.soccer.players Players ON
   Events.playerId = Players.wyId

WHERE
 eventName = 'Free Kick' AND
 subEventName = 'Penalty'

GROUP BY
 playerId, playerName

HAVING
 numPkAtt >= 5

ORDER BY
 PKSuccessRate DESC, numPKAtt DESC
 --predict goal beside shot position and distance
 WITH
Shots AS
(
 SELECT
  *,

  /* 101 is known Tag for 'goals' from goals table */
  (101 IN UNNEST(tags.id)) AS isGoal,

  /* Translate 0-100 (x,y) coordinate-based distances to absolute positions
  using "average" field dimensions of 105x68 before combining in 2D dist calc */
  SQRT(
    POW(
      (100 - positions[ORDINAL(1)].x) * 109/100,
      2) +
    POW(
      (45 - positions[ORDINAL(1)].y) * 54/100,
      2)
     ) AS shotDistance

 FROM
  `soccer.events183`

 WHERE
  /* Includes both "open play" & free kick shots (including penalties) */
  eventName = 'Shot' OR
  (eventName = 'Free Kick' AND subEventName IN ('Free kick shot', 'Penalty'))
)

SELECT
 ROUND(shotDistance, 0) AS ShotDistRound0,

 COUNT(*) AS numShots,
 SUM(IF(isGoal, 1, 0)) AS numGoals,
 AVG(IF(isGoal, 1, 0)) AS goalPct

FROM
 Shots

WHERE
 shotDistance <= 50

GROUP BY
 ShotDistRound0

ORDER BY
 ShotDistRound0

--create predicted models
CREATE OR REPLACE MODEL `soccer.xg_logistic_reg_model_183`
OPTIONS(
 model_type = 'LOGISTIC_REG',
 input_label_cols = ['isGoal']
 ) AS

SELECT
 Events.subEventName AS shotType,

 /* 101 is known Tag for 'goals' from goals table */
 (101 IN UNNEST(Events.tags.id)) AS isGoal,

  `soccer.GetShotDistanceToGoal183`(Events.positions[ORDINAL(1)].x,
   Events.positions[ORDINAL(1)].y) AS shotDistance,

 `soccer.GetShotAngleToGoal183`(Events.positions[ORDINAL(1)].x,
   Events.positions[ORDINAL(1)].y) AS shotAngle

FROM
 `soccer.events183` Events

LEFT JOIN
 `soccer.matches` Matches ON
   Events.matchId = Matches.wyId

LEFT JOIN
 `soccer.competitions` Competitions ON
   Matches.competitionId = Competitions.wyId

WHERE
 /* Filter out World Cup matches for model fitting purposes */
 Competitions.name != 'World Cup' AND
 /* Includes both "open play" & free kick shots (including penalties) */
 (
   eventName = 'Shot' OR
   (eventName = 'Free Kick' AND subEventName IN ('Free kick shot', 'Penalty'))
 )
;
--predict goal probability based on model predicttion
SELECT
 *

FROM
 ML.PREDICT(
   MODEL `soccer.xg_logistic_reg_model_183`,
   (
     SELECT
       Events.subEventName AS shotType,

       /* 101 is known Tag for 'goals' from goals table */
       (101 IN UNNEST(Events.tags.id)) AS isGoal,

       `soccer.GetShotDistanceToGoal183`(Events.positions[ORDINAL(1)].x,
           Events.positions[ORDINAL(1)].y) AS shotDistance,

       `soccer.GetShotAngleToGoal183`(Events.positions[ORDINAL(1)].x,
           Events.positions[ORDINAL(1)].y) AS shotAngle

     FROM
       `soccer.events183` Events

     LEFT JOIN
       `soccer.matches` Matches ON
           Events.matchId = Matches.wyId

     LEFT JOIN
       `soccer.competitions` Competitions ON
           Matches.competitionId = Competitions.wyId

     WHERE
       /* Look only at World Cup matches for model predictions */
       Competitions.name = 'World Cup' AND
       /* Includes both "open play" & free kick shots (including penalties) */
       (
           eventName = 'Shot' OR
           (eventName = 'Free Kick' AND subEventName IN ('Free kick shot', 'Penalty'))
       )
   )
 )
