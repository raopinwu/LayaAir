package laya.particle
{
	import laya.display.Sprite;
	import laya.display.Stage;
	import laya.maths.MathUtil;
	import laya.renders.RenderContext;
	import laya.resource.Texture;
	import laya.utils.Stat;
	import laya.utils.Timer;
	import laya.webgl.WebGL;
	import laya.webgl.WebGLContext;
	import laya.webgl.shader.Shader;
	import laya.webgl.utils.Buffer;
	
	/**
	 * ...
	 * @author laya
	 */
	public class ParticleTemplateWebGL extends ParticleTemplateBase
	{
		protected var _vertices:Float32Array;
		protected var _vertexBuffer:Buffer;
		protected var _indexBuffer:Buffer;
		protected var _floatCountPerVertex:uint = 23;//0~3为CornerTextureCoordinate,4~6为Position,7~9Velocity,10到13为Color,14到16位SizeRotation，17到20位RadiusRadian，21为DurationAddScaleShaderValue,22为Time
		
		protected var _firstActiveElement:int;
		protected var _firstNewElement:int;
		protected var _firstFreeElement:int;
		protected var _firstRetiredElement:int;
		
		protected var _currentTime:Number = 0;
		protected var _drawCounter:int;
		
		public function ParticleTemplateWebGL(parSetting:ParticleSettings)
		{
			settings = parSetting;
		}
		
		protected function initialize():void
		{
			_vertices = new Float32Array(settings.maxPartices * _floatCountPerVertex * 4);
			
			var particleOffset:int;
			for (var i:int = 0; i < settings.maxPartices; i++)
			{
				var random:Number = Math.random();
				var cornerYSegement:Number = 1.0 / settings.textureCount;
				var cornerY:Number;
				
				for (cornerY = 0; cornerY < settings.textureCount; cornerY += cornerYSegement)
				{
					if (random < cornerY + cornerYSegement)
						break;
				}
				particleOffset = i * _floatCountPerVertex * 4;
				_vertices[particleOffset + _floatCountPerVertex * 0 + 0] = -1;
				_vertices[particleOffset + _floatCountPerVertex * 0 + 1] = -1;
				_vertices[particleOffset + _floatCountPerVertex * 0 + 2] = 0;
				_vertices[particleOffset + _floatCountPerVertex * 0 + 3] = cornerY;
				
				_vertices[particleOffset + _floatCountPerVertex * 1 + 0] = 1;
				_vertices[particleOffset + _floatCountPerVertex * 1 + 1] = -1;
				_vertices[particleOffset + _floatCountPerVertex * 1 + 2] = 1;
				_vertices[particleOffset + _floatCountPerVertex * 1 + 3] = cornerY;
				
				_vertices[particleOffset + _floatCountPerVertex * 2 + 0] = 1;
				_vertices[particleOffset + _floatCountPerVertex * 2 + 1] = 1;
				_vertices[particleOffset + _floatCountPerVertex * 2 + 2] = 1;
				_vertices[particleOffset + _floatCountPerVertex * 2 + 3] = cornerY + cornerYSegement;
				
				_vertices[particleOffset + _floatCountPerVertex * 3 + 0] = -1;
				_vertices[particleOffset + _floatCountPerVertex * 3 + 1] = 1;
				_vertices[particleOffset + _floatCountPerVertex * 3 + 2] = 0;
				_vertices[particleOffset + _floatCountPerVertex * 3 + 3] = cornerY + cornerYSegement;
			}
		}
		
		protected function loadContent():void
		{
			_vertexBuffer = new Buffer(WebGLContext.ARRAY_BUFFER, null, null, WebGLContext.DYNAMIC_DRAW);
			
			var indexes:Uint16Array = new Uint16Array(settings.maxPartices * 6);
			
			for (var i:int = 0; i < settings.maxPartices; i++)
			{
				indexes[i * 6 + 0] = (i * 4 + 0);
				indexes[i * 6 + 1] = (i * 4 + 1);
				indexes[i * 6 + 2] = (i * 4 + 2);
				
				indexes[i * 6 + 3] = (i * 4 + 0);
				indexes[i * 6 + 4] = (i * 4 + 2);
				indexes[i * 6 + 5] = (i * 4 + 3);
			}
			
			_indexBuffer = new Buffer(WebGLContext.ELEMENT_ARRAY_BUFFER, null);
			_indexBuffer.length = 0;
			_indexBuffer.append(indexes);
			_indexBuffer.upload();
		}
		
		public function update(elapsedTime:int):void
		{
			_currentTime += elapsedTime / 1000;
			retireActiveParticles();
			freeRetiredParticles();
			
			if (_firstActiveElement == _firstFreeElement)
				_currentTime = 0;
			
			if (_firstRetiredElement == _firstActiveElement)
				_drawCounter = 0;
		}
		
		private function retireActiveParticles():void
		{
			var particleDuration:Number = settings.duration;
			while (_firstActiveElement != _firstNewElement)
			{
				var index:int = _firstActiveElement * _floatCountPerVertex * 4 + 22;//22为Time
				var particleAge:Number = _currentTime - _vertices[index];
				
				if (particleAge < particleDuration)
					break;
				
				_vertices[index] = _drawCounter;
				
				_firstActiveElement++;
				
				if (_firstActiveElement >= settings.maxPartices)
					_firstActiveElement = 0;
			}
		}
		
		private function freeRetiredParticles():void
		{
			while (_firstRetiredElement != _firstActiveElement)
			{
				var age:int = _drawCounter - _vertices[_firstRetiredElement * _floatCountPerVertex * 4 + 22];//22为Time,注意Numver到Int类型转换,JS中可忽略
				//GPU从不滞后于CPU两帧，出于显卡驱动BUG等安全因素考虑滞后三帧
				if (age < 3)
					break;
				
				_firstRetiredElement++;
				
				if (_firstRetiredElement >= settings.maxPartices)
					_firstRetiredElement = 0;
			}
		}
		
		public function addNewParticlesToVertexBuffer():void
		{
			_vertexBuffer.length = 0;
			_vertexBuffer.setdata(_vertices);
			
			var start:int;
			if (_firstNewElement < _firstFreeElement)
			{
				// 如果新增加的粒子在Buffer中是连续的区域，只upload一次
				start = _firstNewElement * 4 * _floatCountPerVertex * 4;
				_vertexBuffer.subUpload(start, start, start + (_firstFreeElement - _firstNewElement) * 4 * _floatCountPerVertex * 4);
			}
			else
			{
				//如果新增粒子区域超过Buffer末尾则循环到开头，需upload两次
				start = _firstNewElement * 4 * _floatCountPerVertex * 4;
				_vertexBuffer.subUpload(start, start, start + (settings.maxPartices - _firstNewElement) * 4 * _floatCountPerVertex * 4);
				
				if (_firstFreeElement > 0)
				{
					_vertexBuffer.setNeedUpload();
					_vertexBuffer.subUpload(0, 0, _firstFreeElement * 4 * _floatCountPerVertex * 4);
				}
			}
			_firstNewElement = _firstFreeElement;
		}
		
		public override function addParticleArray(position:Float32Array, velocity:Float32Array):void//由于循环队列判断算法，当下一个freeParticle等于retiredParticle时不添加例子，意味循环队列中永远有一个空位。（由于此判断算法快速、简单，所以放弃了使循环队列饱和的复杂算法（需判断freeParticle在retiredParticle前、后两种情况并不同处理））
		{
			var nextFreeParticle:int = _firstFreeElement + 1;
			
			if (nextFreeParticle >= settings.maxPartices)
				nextFreeParticle = 0;
			
			if (nextFreeParticle === _firstRetiredElement)
				return;
			
			var particleData:ParticleData = ParticleData.Create(settings, position, velocity, _currentTime);
			
			var startIndex:int = _firstFreeElement * _floatCountPerVertex * 4;
			for (var i:int = 0; i < 4; i++)
			{
				var j:int, offset:int;
				for (j = 0, offset = 4; j < 3; j++)
					_vertices[startIndex + i * _floatCountPerVertex + offset + j] = particleData.position[j];
				
				for (j = 0, offset = 7; j < 3; j++)
					_vertices[startIndex + i * _floatCountPerVertex + offset + j] = particleData.velocity[j];
				
				for (j = 0, offset = 10; j < 4; j++)
					_vertices[startIndex + i * _floatCountPerVertex + offset + j] = particleData.color[j];
				
				for (j = 0, offset = 14; j < 3; j++)//StartSize,EndSize,Rotation
					_vertices[startIndex + i * _floatCountPerVertex + offset + j] = particleData.sizeRotation[j];
				
				for (j = 0, offset = 17; j < 4; j++)//StartRadius,EndRadius,EndHorizontalRadian,EndVerticleRadian
					_vertices[startIndex + i * _floatCountPerVertex + offset + j] = particleData.radiusRadian[j];//StartRadius
				
				_vertices[startIndex + i * _floatCountPerVertex + 21] = particleData.durationAddScale;
				
				_vertices[startIndex + i * _floatCountPerVertex + 22] = particleData.time;
			}
			
			_firstFreeElement = nextFreeParticle;
		}
	
	}
}