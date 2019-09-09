import 'package:flutter_mvvm/provider/view_state_obj_model.dart';
import 'package:flutter_mvvm/model/ai/common_model.dart';
import 'package:flutter_mvvm/model/ai/sentence_model.dart';
import 'package:flutter_mvvm/ui/page/ai/intensive_learning.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_mvvm/utils/log_utils.dart';
import 'package:flutter_mvvm/base/route_page_builder.dart';
import 'package:flutter_mvvm/components/ai/shared/pause_dialog.dart';
import 'package:flutter_mvvm/base/audio_player_factory.dart';
import 'package:flutter_mvvm/base/base_channel.dart';
import 'package:flutter_mvvm/res/strings.dart';
import 'package:flutter_mvvm/model/ai/module_model.dart';
import 'package:flutter_mvvm/model/ai/word_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:oktoast/oktoast.dart';
import 'dart:convert';
import 'dart:async';


class IntensiveViewModel extends ViewStateObjModel<CommonModel> with BaseChannel{
  BottomState _bottomState = BottomState.BottomNav ,
              _rippleStateFrom ; // 记录水波纹来缘
  bool _bottomNavLeftVisibly = true ,
      _bottomNavRightVisibly = true ,
      _bottomNavGifVisibly = false ,
      _rippleClickable = true ,
      _isSupportUpWardAnimation = true,
      _executeUpWardAnimation = false ; // 是否开启动画，true之前必须设置为false,否则不生效
  int _maxProgress = 0 , _curProgress = 0 ;
  String _rippleNotice = Strings.string_click_wave_stop_record;
  BuildContext _context ;
  PageController _pageController = PageController();
  var _pageViewData = <ModuleModel>[];
  PageModuleType _pageType = PageModuleType.PageSentence;
  bool _voiceVisibly = true,
       _playVisibly = false ,
       _scoreVisibly = false;


  // 自定义初始化方法
  initModelData(BuildContext context) async {
    // 重写initializeData的方法,进行事件的EventChannel/MethodChannel的注册
    // eventChannel 此时可以直接调用eventChannel发送event
    // methodChannel 直接调用methodChannel调用native方法
    registerEventChannel();
    registerMethodChannel();

    _context = context ;
    setLoading(loading: false);
    data = await loadData();
    _parseCommonModelToPageModel();
    _maxProgress = _pageViewData.length;
    _curProgress = 0 ;
    notifyListeners();
    _playSentenceAudio();
  }

  @override
  void dispose() {
    disposeSubscription();
    _pageController?.dispose();
    // 此时不可dispose，只有退出整个app的时候dispose audioPlayer
    // audioPlayerFactory.dispose();
    super.dispose();
  }

  @override
  Future<CommonModel> loadData() async {
    String value = await DefaultAssetBundle.of(_context).loadString("assets/zip/intensive_learning.json");
    List _json = json.decode(value);
    LogUtils.d(tag: "loadData",msg: "$_json");
    List<SentenceModel> sentences = _json.map((item) => SentenceModel.fromJson(item)).toList();
    var _commModel = CommonModel(sentences: sentences);
    return Future.value(_commModel);
  }

  // 解析数据，封装数据
  void _parseCommonModelToPageModel(){
     if(data != null && data.sentences.isNotEmpty){
        for(SentenceModel sentence in data.sentences){
          _pageViewData.add(ModuleModel(type: PageModuleType.PageSentence, data: sentence, audio: sentence.sentenceEnAuidio,),); // 句子学习
          if(sentence.words.isNotEmpty){
             for(WordModel word in sentence.words){
               word.wordImgUrl = "assets/zip/${word.wordImg}";
               _pageViewData.add(ModuleModel(type: PageModuleType.PageWord, data: word, audio: word.wordAudio,),);// 单词学习
             }
          }
          _pageViewData.add(ModuleModel(type: PageModuleType.PageAssess, data: sentence, audio: sentence.sentenceEnAuidio,evaluationTime: 2),); // 句子考核
        }
     }
  }

  ModuleModel getPageViewDataToIndex(int index) => _pageViewData.length > 0 ? _pageViewData[index] : ModuleModel();

  // 监听event事件流
  @override
  void onEventListener(event) {
    super.onEventListener(event);
  }

  // 监听native call flutter
  @override
  Future<dynamic> onPlatformCallHandler(MethodCall call) async {
    return super.onPlatformCallHandler(call);
  }

  @override
  int getCurProgress() => _curProgress ;

  @override
  int getMaxProgress() => _maxProgress ;

  @override
  void onPausePressed() async {
    debugPrint("[onPausePressed] --- 暂停");
    bool _playing = false ;
    if(audioPlayerFactory.playState() == AudioPlayerState.PLAYING){
      _playing = true ;
      bool _result = await audioPlayerFactory.pauseAudio();
      if(_result){
        _bottomNavGifVisibly = false ;
        notifyListeners();
      }
    }
    showDialog(
      context: _context,
      builder: (BuildContext context) => PausePage(),
    ).then((item){
      if(item == PausePageAction.again){// 再来一次
        showToast("重来");
        Navigator.of(_context).pushReplacement(FadeRoutePage(child:IntensiveLearning()));
      } else if(item == PausePageAction.continueLearning){// 继续
        showToast("继续");
        if(_playing){
          audioPlayerFactory.resumeAudio();
        }
      } else { // 退出
        showToast("退出");
        audioPlayerFactory.stopAudio().then((val){
          Navigator.of(_context).pop();
        });
      }
    });
  }

  // 获取ScrollController
  PageController getController() => _pageController ;

  // 获取PageView的count
  int getPageViewCount() => _maxProgress ;

  //点击底部导航
  void onBottomNavPressed(type){
    debugPrint("[onBottomNavPressed] --- type: $type");
    _isSupportUpWardAnimation = true ;
    if(_executeUpWardAnimation){
      _executeUpWardAnimation = false ;
    }
    switch(type){
      case Strings.string_tag_previous:
        _curProgress -= 1 ;
        if(_curProgress < 0){
          _curProgress = 0 ;
        }
        _animJumpToPage();

        break;
      case Strings.string_tag_sound:
        _playSentenceAudio();

        break;
      case Strings.string_tag_record:
        _bottomState = BottomState.RecordRipple;
        _rippleStateFrom = BottomState.BottomNav ;
        _rippleNotice = Strings.string_click_wave_stop_record ;
        notifyListeners();
        audioPlayerFactory.playAssetAudio(assetAudio: "record_down.wav",prefix: "audio/");

        break;
      case Strings.string_tag_next:
        _curProgress += 1 ;
        if(_curProgress > _maxProgress - 1){
          _curProgress = _maxProgress - 1;
        }
        _animJumpToPage();

        break;
    }
  }

  // 考核播放按钮可见
  bool assessPlayVisibly() => _playVisibly ;

  // 考核音频按钮可见
  bool assessVoiceVisibly() => _voiceVisibly ;

  // 考核分数部分可见
  bool assessScoreVisibly() => _scoreVisibly ;

  // 左边导航
  bool bottomNavLeftVisibly() => _bottomNavLeftVisibly && _pageType != PageModuleType.PageSentence;

  // 右边导航
  bool bottomNavRightVisibly() => _bottomNavRightVisibly ;

  // 底部gif显示
  bool bottomNavGifVisibly() => _bottomNavGifVisibly ;

  // 水波纹是否可点击
  bool getRippleClickable() => _rippleClickable;

  // 水波纹上方文案
  String getRippleNotice() => _rippleNotice ;

  // 点击水波纹
  void onRipplePressed(){
    _rippleNotice = Strings.string_click_wave_audio_parse ;
    _rippleClickable = false ;
    _isSupportUpWardAnimation = false ;
    audioPlayerFactory.playAssetAudio(assetAudio: "record_up.wav",prefix: "audio/");
    notifyListeners();
    // 模拟打分操作
    Future.delayed(Duration(milliseconds: 4000),(){
      _rippleClickable = true ;
      _bottomState = _rippleStateFrom ;
      notifyListeners();
      if(_pageType == PageModuleType.PageAssess){
        int _time = _pageViewData[_curProgress].time;
        _time -= 1 ;
        _pageViewData[_curProgress].time = _time ;
        if(_time <= 0){
          onBottomNavPressed(Strings.string_tag_next);
          return;
        }
      }
      showToast("Bad!");
    });
  }

  // PageView 滑动到Page
  void _animJumpToPage(){
    _pageType = _pageViewData[_curProgress].type;
    _bottomState = _pageType == PageModuleType.PageAssess ? BottomState.RecordButton : BottomState.BottomNav ;
    notifyListeners();
    _pageController.animateToPage(_curProgress,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeIn,
    ).then((p){
      _executeUpWardAnimation = true ;
      notifyListeners();
      _playSentenceAudio();
    });
  }

  //获取底部状态
  BottomState getBottomState() => _bottomState;

  // 播放句子音频
  void _playSentenceAudio({String fileName}) async {
    _bottomNavGifVisibly = true;
    _playVisibly = false ;
    notifyListeners();
    bool _result = await audioPlayerFactory.playAssetAudio(
        assetAudio: fileName ?? "${_pageViewData[_curProgress].audio}",
        prefix: "zip/",
        listenPlayCompletion: (){
          _bottomNavGifVisibly = false ;
          _playVisibly = true ;
          notifyListeners();
        }
    );
    if(!_result){
      _bottomNavGifVisibly = false ;
      _playVisibly = true ;
      notifyListeners();
    }
  }

  // 是否支持上移动画
  bool isSupportFadeAnimation() => _isSupportUpWardAnimation;

  // 是否执行上移动动画
  bool executeUpWardAnimation() => _executeUpWardAnimation ;

  // 点击考核部分的录音
  void onPressedRecordBtn(){
    _rippleStateFrom = BottomState.RecordButton ;
    _bottomState = BottomState.RecordRipple ;
    _rippleNotice = Strings.string_click_wave_stop_record ;
    notifyListeners();
    audioPlayerFactory.playAssetAudio(assetAudio: "record_down.wav",prefix: "audio/");
  }


}

enum BottomState{
  BottomNav, //底部导航
  RecordRipple,//录音水波纹
  EmptyView, // 空白
  RecordButton,// 录音按钮
}