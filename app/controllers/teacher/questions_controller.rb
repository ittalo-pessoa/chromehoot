module Teacher
  class QuestionsController < BaseController
    before_action do
      @quiz = current_user.quizzes.find(params[:quiz_id])
      @question = @quiz.questions.find(params[:id]) if params[:id]
    end
    def new
      @question = @quiz.questions.new(time_limit_seconds: 30)
      5.times { |i| @question.choices.build(position: i + 1) }
    end
    def edit
      (5 - @question.choices.size).times { |i| @question.choices.build(position: @question.choices.size + 1) }
    end
    def create
      @quiz.with_lock do
        @question = @quiz.questions.new(question_params)
        @question.position = (@quiz.questions.maximum(:position) || 0) + 1
        save_question(:new)
      end
    end
    def update
      @quiz.with_lock do
        @question.assign_attributes(question_params)
        save_question(:edit)
      end
    end
    def destroy
      @quiz.with_lock { @question.destroy! }
      redirect_to teacher_quiz_path(@quiz), notice: "Questão excluída.", status: :see_other
    end
    def move
      @quiz.with_lock do
        list = @quiz.questions.to_a
        index = list.index(@question)
        target = params[:direction] == "up" ? index - 1 : index + 1
        if target.between?(0, list.size - 1)
          list[index], list[target] = list[target], list[index]
          offset = (@quiz.questions.maximum(:position) || 0) + 10
          list.each_with_index { |q, i| q.update_column(:position, offset + i) }
          list.each_with_index { |q, i| q.update_column(:position, i + 1) }
        end
      end
      redirect_to teacher_quiz_path(@quiz), status: :see_other
    end

    private
    def question_params
      permitted = params.require(:question).permit(:statement, :time_limit_seconds, :image, choices_attributes: [ :id, :text, :correct, :_destroy ])
      permitted.fetch(:choices_attributes, {}).each_pair.with_index do |(_, item), index|
        item[:position] = index + 1
        item[:_destroy] = "1" if item[:id].present? && item[:text].blank?
      end
      permitted
    end
    def save_question(template)
      if @question.save
        redirect_to teacher_quiz_path(@quiz), notice: "Questão salva."
      else
        render template, status: :unprocessable_entity
      end
    end
  end
end
