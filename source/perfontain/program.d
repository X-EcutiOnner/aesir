module perfontain.program;

import
		std.experimental.all,

		core.bitop,

		perfontain.opengl,
		perfontain,

		tt.error,
		tt.logger : log;


enum
{
	PROG_DATA_MODEL		= 1,
	PROG_DATA_COLOR		= 2,
	PROG_DATA_NORMAL	= 4,
	PROG_DATA_LIGHTS	= 8,
	PROG_DATA_SM_MAT	= 16,
}

final class Program : RCounted
{
	this(Shader[] shaders)
	{
		_id = glCreateProgram();

		foreach(s; shaders)
		{
			glAttachShader(_id, s.id);
		}

		glLinkProgram(_id);

		foreach(s; shaders)
		{
			s.parseAttribs;
			glDetachShader(_id, s.id);
		}

		{
			ubyte f;

			auto arr =
			[
				tuple(`pe_transforms.pe_shadow_matrix`, PROG_DATA_SM_MAT),
				tuple(`pe_transforms.transforms[].model`, PROG_DATA_MODEL),
				tuple(`pe_transforms.transforms[].color`, PROG_DATA_COLOR),
				tuple(`pe_transforms.transforms[].normal`, PROG_DATA_NORMAL),
				tuple(`pe_transforms.transforms[].lightStart`, PROG_DATA_LIGHTS),
			];

			foreach(s; shaders)
			{
				foreach(a; arr)
				{
					if(a[0] in s.attribs)
					{
						f |= a[1];
						break;
					}
				}
			}

			flags = f;
		}
	}

	~this()
	{
		unbind;

		foreach(u; _unis.values.filter!(a => a && a.idx >= 0))
		{
			u.data = null;
			btr(&_ssbo, u.idx);
		}

		glDeleteProgram(_id);
	}

	void bind()
	{
		bind(_id);
	}

	static unbind()
	{
		bind(0);
	}

	void send(T)(string name, ref in T value)
	{
		auto s = locationOf(name);

		debug
		{
			if(!s) return;
		}

		static if(is(T : int))
		{
			glProgramUniform1i(_id, s.loc, value);
		}
		else static if(is(T == ulong))
		{
			glProgramUniform2uiv(_id, s.loc, 1, cast(uint*)&value);
		}
		else static if(is(T == Vector3))
		{
			glProgramUniform3fv(_id, s.loc, 1, value.ptr);
		}
		else static if(is(T == Vector4))
		{
			glProgramUniform4fv(_id, s.loc, 1, value.ptr);
		}
		else static if(is(T == Matrix4))
		{
			glProgramUniformMatrix4fv(_id, s.loc, 1, false, value.ptr);
		}
		else
		{
			static assert(false);
		}
	}

	void ssbo(string name, in void[] data, bool dynamic = true)
	{
		assert(data.length);

		if(auto s = locationOf(name, true))
		{
			bool b = !s.data;

			if(b)
			{
				s.data = new VertexBuffer(-1, dynamic ? VBO_DYNAMIC : 0);
			}

			s.data.realloc(cast(uint)data.length, data.ptr);

			if(b)
			{
				glShaderStorageBlockBinding(_id, s.loc, s.idx);
				glBindBufferBase(GL_SHADER_STORAGE_BUFFER, s.idx, s.data.id);
			}
		}
	}

	auto minLen(string name)
	{
		if(auto r = locationOf(name, true))
		{
			return r.len;
		}

		assert(false);
	}

	const ubyte flags;
private:
	static bind(uint id)
	{
		if(set(PEstate._prog, id))
		{
			glUseProgram(id);
		}
	}

	auto locationOf(string name, bool ssb = false)
	{
		if(auto u = name in _unis)
		{
			return *u;
		}

		auto n = name.toStringz;
		int loc = ssb ? glGetProgramResourceIndex(_id, GL_SHADER_STORAGE_BLOCK, n) : glGetUniformLocation(_id, n);

		UniformData *s;

		if(loc < 0)
		{
			log.warning("can't get %s location for `%s' variable", ssb ? `SSBO` : `uniform`, name);
		}
		else
		{
			s = new UniformData;
			s.loc = loc;

			if(ssb)
			{
				auto prop = GL_BUFFER_DATA_SIZE;
				glGetProgramResourceiv(_id, GL_SHADER_STORAGE_BLOCK, loc, 1, &prop, 1, null, &s.len);

				s.idx = cast(byte)bsf(~_ssbo);
				btc(&_ssbo, s.idx);
			}
		}

		_unis[name] = s;
		_unis.rehash;

		return s;
	}

	struct UniformData
	{
		RC!VertexBuffer data;

		int
			loc,
			len;

		byte idx = -1;
	}

	__gshared size_t _ssbo;

	uint _id;
	UniformData *[string] _unis;
}
