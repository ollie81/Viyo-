import 'package:flutter/material.dart';
import '../models/viyo_mission.dart';

/// Routes a mission to the action that can actually complete it.
///
/// This keeps the mission UI from merely displaying text: tapping a mission
/// takes the creator to the relevant part of Viyo.
class ViyoMissionRouter {
  const ViyoMissionRouter();

  Future<void> openMission(
    BuildContext context,
    ViyoMission mission,
  ) async {
    switch (mission.action) {
      case ViyoMissionAction.watchVideos:
        Navigator.pushNamed(context, '/videos');
        break;
      case ViyoMissionAction.followCreator:
        Navigator.pushNamed(context, '/discover');
        break;
      case ViyoMissionAction.likePosts:
        Navigator.pushNamed(context, '/home');
        break;
      case ViyoMissionAction.createPost:
        Navigator.pushNamed(context, '/create');
        break;
      case ViyoMissionAction.completeProfile:
        Navigator.pushNamed(context, '/profile/edit');
        break;
      case ViyoMissionAction.dailyCheckIn:
        // Check-in should be completed by the backend. The UI can take the
        // user to the mission/check-in surface without awarding coins itself.
        Navigator.pushNamed(context, '/missions/check-in');
        break;
    }
  }
}
